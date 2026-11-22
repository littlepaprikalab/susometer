// The demo film's machinery (see test/demo_film_test.dart): drives the real
// app on fake time, one frame at a time, and pipes each frame to ffmpeg.
// Everything a viewer hears (host lines, sounds) is logged with its time in
// the video, for tool/demo_video/mix.py to lay under the picture.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/audio/host_audio.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game_root.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/voice/speech_service.dart';

import '../fakes.dart';
import '../synthetic.dart';
import 'stage.dart';

enum Mood { neutral, happy, surprised, nervous, laugh }

/// Something said: by a stand-in (their speech bubble) or by the host.
class Line {
  Line(this.speaker, this.text, this.startMs, this.durMs, {this.color});

  final String speaker;
  final String text;
  final int startMs;
  final int durMs;
  final Color? color;

  /// How much of it has been said at [now], 0–1.
  double said(int now) =>
      durMs <= 0 ? 1 : ((now - startMs) / durMs).clamp(0.0, 1.0);
}

/// A stand-in person. A real clip replaces them shot by shot.
class Actor {
  Actor(
    this.name, {
    required this.skin,
    required this.hair,
    required this.shirt,
    this.hairStyle = 0,
  });

  final String name;
  final Color skin;
  final Color hair;
  final Color shirt;

  /// 0 short, 1 long, 2 bun, 3 curly.
  final int hairStyle;

  Mood mood = Mood.neutral;
  bool talking = false;

  /// Legit / Sus paddle held up (Call it!).
  bool? paddleSus;

  /// Eyes closed until this time (the hot seat blinks when the fake SDK
  /// says so; everyone else blinks by themselves).
  int blinkUntil = 0;
  Line? line;
}

/// One stretch of the "room" picture: the slot a real clip goes in.
class Shot {
  Shot(this.id, this.what, this.startMs);

  final String id;
  final String what;
  final int startMs;
  int endMs = 0;
  final List<String> lines = [];

  Map<String, Object?> toJson() => {
    'id': id,
    'what': what,
    'start': startMs / 1000,
    'end': endMs / 1000,
    'lines': lines,
  };
}

class AudioEvent {
  AudioEvent(
    this.file,
    this.startMs,
    this.durMs, {
    this.gain = 1,
    this.clockMs = 0,
    this.unfilmed = false,
  });

  /// When it started on the game's clock, and whether that was in a stretch
  /// the film skipped (see [Film.fast]).
  final int clockMs;
  bool unfilmed;

  final String file;
  final int startMs;
  final int durMs;
  final double gain;

  /// Cut short here (the host was interrupted, or the film jumped ahead).
  int? cutMs;

  Map<String, Object?> toJson() => {
    'file': file,
    'start': startMs / 1000,
    'gain': gain,
    if (cutMs != null) 'cut': cutMs! / 1000,
  };
}

/// A full-screen card between scenes.
class TitleCard {
  const TitleCard(this.title, this.lines, {this.kicker});

  final String? kicker;
  final String title;
  final List<String> lines;
}

class Film {
  Film(this.tester, this.name);

  final WidgetTester tester;

  /// `solo` or `party`: names the output files.
  final String name;

  static const fps = 30;
  static const size = Size(1920, 1080);

  /// Where the videos go. Unset: nothing is rendered (a dry run that only
  /// plays the script through, for tuning it).
  static final String? outDir = Platform.environment['FILM_OUT'];

  /// A command that reads text on stdin and takes `-f out.wav` (piper), for
  /// the host's voice. Unset: the host is captions only.
  static final String? piper = switch (Platform.environment['FILM_PIPER']) {
    null || '' => null,
    final command => command,
  };

  final presage = FilmPresage();
  final speech = FakeSpeech();
  final device = FakeDevice();
  late final host = FilmHost(this);
  late final AppServices services;
  GameController get game => services.game;

  // What the stage shows.
  final tick = ValueNotifier<int>(0);
  List<Actor> cast = [];
  String chapter = '';
  String step = '';
  String note = '';
  TitleCard? card;
  Line? hostLine;
  Line? lastLine;
  Shot? shot;
  final List<(Offset, int)> taps = [];
  (String, int)? jump;

  /// The stand-in in the hot seat: the app's current player, from their
  /// consent screen to their last verdict.
  Actor? get hotSeat {
    const before = {
      GamePhase.lobby,
      GamePhase.howToPlay,
      GamePhase.permissions,
    };
    const after = {GamePhase.leaderboard, GamePhase.replay};
    if (game.turns.isEmpty ||
        before.contains(game.phase) ||
        after.contains(game.phase)) {
      return null;
    }
    final n = game.currentPlayer.name;
    for (final a in cast) {
      if (a.name == n) return a;
    }
    return null;
  }

  Actor actor(String name) => cast.firstWhere((a) => a.name == name);

  int get now => clock.now().millisecondsSinceEpoch;

  // Recording.
  bool get rendering => outDir != null;
  bool _fast = false;

  /// Frames are being captured right now.
  bool get recording => rendering && !_fast;
  int frames = 0;
  int get videoMs => (frames * 1000 / fps).round();
  final shots = <Shot>[];
  final audio = <AudioEvent>[];
  final _key = GlobalKey();

  /// A monospace font was found for the Proof Panel (it asks for Menlo,
  /// which a test has no access to; without one its text is boxes).
  bool hasMono = false;

  static const _monoFonts = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf',
    '/System/Library/Fonts/Supplemental/Courier New.ttf',
    '/System/Library/Fonts/SFNSMono.ttf',
    '/Library/Fonts/Courier New.ttf',
  ];
  Process? _ffmpeg;
  int _usDebt = 0;

  Future<void> start() async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    presage.film = this;
    CameraPreview.debugStandIn = (_) => CameraStandIn(this);
    addTearDown(() => CameraPreview.debugStandIn = null);
    services = AppServices(
      presage: presage,
      speech: speech,
      device: device,
      host: host,
      haptics: FakeHaptics(),
    );
    await tester.runAsync(() async {
      for (final path in _monoFonts) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        await (FontLoader(
          'Menlo',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        hasMono = true;
        break;
      }
    });
    presage.begin();
    await tester.pumpWidget(RepaintBoundary(key: _key, child: Stage(this)));
    await tester.pump();
    if (rendering) {
      Directory(outDir!).createSync(recursive: true);
      await tester.runAsync(() async {
        final p = _ffmpeg = await Process.start('ffmpeg', [
          '-y',
          '-loglevel',
          'error',
          '-f',
          'rawvideo',
          '-pix_fmt',
          'rgba',
          '-s',
          '${size.width.round()}x${size.height.round()}',
          '-r',
          '$fps',
          '-i',
          '-',
          '-c:v',
          'libx264',
          '-preset',
          'medium',
          '-crf',
          '17',
          '-pix_fmt',
          'yuv420p',
          '-movflags',
          '+faststart',
          '$outDir/$name.video.mp4',
        ]);
        unawaited(p.stderr.pipe(stderr));
        unawaited(p.stdout.drain<void>());
      });
    }
  }

  Future<void> finish() async {
    _closeShot();
    if (rendering) {
      await tester.runAsync(() async {
        await _ffmpeg!.stdin.close();
        final code = await _ffmpeg!.exitCode;
        if (code != 0) throw StateError('ffmpeg exited with $code');
      });
      File('$outDir/$name.events.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({
          'name': name,
          // Rendered to follow a real recording (demo_film_test.dart).
          'withReal': Platform.environment['FILM_WITH_REAL'] == '1',
          'fps': fps,
          'frames': frames,
          'duration': videoMs / 1000,
          'room': [
            Stage.room.left,
            Stage.room.top,
            Stage.room.width,
            Stage.room.height,
          ],
          'shots': [for (final s in shots) s.toJson()],
          'audio': [for (final a in audio) a.toJson()],
        }),
      );
    }
    presage.end();
    await tester.pumpWidget(const SizedBox());
    game.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  // ---------------------------------------------------------------------------
  // Time

  /// Plays [ms] of the game. Recording: one frame at a time. Fast: in
  /// 100 ms steps, nothing captured.
  Future<void> run(int ms) async {
    if (!recording) {
      for (var i = 0; i < (ms / 100).ceil(); i++) {
        await _step(100000);
      }
      return;
    }
    final n = math.max(1, (ms * fps / 1000).round());
    for (var i = 0; i < n; i++) {
      // 33 333 µs, and the odd one out so 30 frames make a second.
      _usDebt += 1000000;
      final us = _usDebt ~/ fps;
      _usDebt -= us * fps;
      await _step(us);
      await _capture();
    }
  }

  Future<void> until(bool Function() cond, {int maxMs = 120000}) async {
    final start = now;
    while (!cond()) {
      await run(100);
      if (now - start > maxMs) {
        fail('Film: timed out (phase ${game.phase})');
      }
    }
  }

  /// Plays [body] without filming it: the video jumps ahead, with a chip
  /// saying how far.
  Future<void> fast(Future<void> Function() body, {String? label}) async {
    final was = _fast;
    final from = now;
    if (!was) {
      for (final a in audio) {
        if (a.cutMs == null && a.startMs + a.durMs > videoMs) {
          a.cutMs = videoMs - a.startMs;
        }
      }
      host.cutCaptions();
    }
    _fast = true;
    await body();
    _fast = was;
    if (!was) {
      // Sounds from the skipped stretch aren't in the film, except one that
      // began as it ended (the drumroll that starts the countdown).
      audio.removeWhere((a) => a.unfilmed && now - a.clockMs > 250);
      for (final a in audio) {
        a.unfilmed = false;
      }
      host.restartLine();
      final s = ((now - from) / 1000).round();
      final skipped = s >= 60 ? '${s ~/ 60} min ${s % 60} s' : '$s s';
      jump = (label ?? '$skipped later', now + 1600);
      for (final a in cast) {
        a.line = null;
      }
    }
  }

  Future<void> _step(int us) async {
    final seat = hotSeat;
    if (seat != null) presage.expr = exprFor(seat.mood);
    tick.value++;
    await tester.pump(Duration(microseconds: us));
    await host.service();
  }

  Future<void> _capture() async {
    final boundary =
        _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      final sink = _ffmpeg!.stdin;
      sink.add(data!.buffer.asUint8List());
      await sink.flush();
    });
    frames++;
  }

  // ---------------------------------------------------------------------------
  // Direction

  /// A new shot of the room: the slot a real clip of this moment replaces.
  void cut(String id, String what) {
    _closeShot();
    shot = Shot('$name-$id', what, videoMs);
    if (recording) shots.add(shot!);
  }

  void _closeShot() {
    final s = shot;
    if (s != null) s.endMs = videoMs;
  }

  /// Shows a full-screen card for [ms].
  Future<void> showCard(TitleCard c, int ms) async {
    _closeShot();
    shot = null;
    card = c;
    await run(ms);
    card = null;
  }

  bool get _guarded {
    final screen = find.byKey(phaseTapGuardKey);
    if (screen.evaluate().isNotEmpty &&
        tester.widget<IgnorePointer>(screen).ignoring) {
      return true;
    }
    final sheet = find.byKey(sheetTapGuardKey);
    return sheet.evaluate().isNotEmpty &&
        tester.widget<AbsorbPointer>(sheet).absorbing;
  }

  /// A finger taps [target] (a label, or a finder), like a player would:
  /// after the screen's tap guard, with the button held a moment.
  Future<void> tap(Object target, {int at = 0, int after = 250}) async {
    final all = target is Finder ? target : find.text(target as String);
    for (var i = 0; i < 40 && _guarded; i++) {
      await run(50);
    }
    expect(all, findsWidgets, reason: 'Film: nothing to tap for $target');
    final finder = all.at(at);
    // Scroll only when it's out of view: ensureVisible would otherwise bring
    // it to the top of the list, moving the page for no reason.
    final view = find.ancestor(of: finder, matching: find.byType(Scrollable));
    final r = tester.getRect(finder);
    final shown =
        view.evaluate().isEmpty ||
        tester.getRect(view.first).inflate(1).contains(r.topLeft) &&
            tester.getRect(view.first).inflate(1).contains(r.bottomRight);
    if (!shown) await tester.ensureVisible(finder);
    await run(50);
    final p = tester.getCenter(finder);
    taps.add((p, now));
    final gesture = await tester.startGesture(p);
    await run(120);
    await gesture.up();
    // Negative: the caller takes over right at the tap (to skip ahead
    // before whatever it started is heard).
    if (after >= 0) await run(after);
  }

  /// A finger drags the scrollable under [on] by [dy] over [ms], filmed.
  Future<void> scroll(Finder on, double dy, {int ms = 900}) async {
    final p = tester.getCenter(on.first);
    final gesture = await tester.startGesture(p);
    const steps = 18;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, dy / steps));
      await run(ms ~/ steps);
    }
    await gesture.up();
    await run(400);
  }

  /// Types [text] into the lobby's name field, letter by letter.
  Future<void> typeName(String text) async {
    final field = find.byKey(const ValueKey('addContestant'));
    await tester.showKeyboard(field);
    for (var i = 1; i <= text.length; i++) {
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: text.substring(0, i),
          selection: TextSelection.collapsed(offset: i),
        ),
      );
      await run(90);
    }
    await run(200);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await run(350);
  }

  /// [who] says [text] out loud over [ms]. The phone's recognizer hears it
  /// word by word (unless [heard] is off), and the hot-seat player's
  /// talking flag is on while they speak.
  Future<void> speak(
    Actor who,
    String text, {
    int? ms,
    bool heard = true,
    int linger = 500,
  }) async {
    final dur = ms ?? 500 + 62 * text.length;
    final line = Line(who.name, text, now, dur, color: who.shirt);
    who
      ..line = line
      ..talking = true;
    lastLine = line;
    if (recording) shot?.lines.add('${who.name}: “$text”');
    final hot = identical(who, hotSeat);
    if (hot) presage.talk(true);
    final words = text.split(' ');
    var said = 0;
    final start = now;
    while (now - start < dur) {
      // The recognizer runs a little behind the voice.
      final due = ((now - start - 250) / (dur - 250) * words.length)
          .ceil()
          .clamp(0, words.length);
      if (heard && due > said) {
        said = due;
        _hear(words.take(said).join(' '));
      }
      await run(100);
    }
    if (heard && said < words.length) _hear(text);
    who.talking = false;
    if (hot) presage.talk(false);
    await run(linger);
  }

  void _hear(String text) => speech.controller.add(
    SpeechText(text: text, segment: speech.segment, isFinal: false, tMs: now),
  );

  void debug(String message) {
    // ignore: avoid_print
    print('[film $name ${(videoMs / 1000).toStringAsFixed(1)}s] $message');
  }
}

/// SmartSpectra expression scores for a stand-in's mood.
Map<String, double> exprFor(Mood m) => switch (m) {
  Mood.neutral => const {'neutral': 0.8, 'happy': 0.1, 'surprise': 0.04},
  Mood.happy => const {'happy': 0.7, 'neutral': 0.2, 'surprise': 0.04},
  Mood.laugh => const {'happy': 0.85, 'neutral': 0.1, 'surprise': 0.04},
  Mood.surprised => const {'surprise': 0.7, 'neutral': 0.15, 'fear': 0.1},
  Mood.nervous => const {'fear': 0.55, 'surprise': 0.3, 'neutral': 0.1},
};

/// A made-up SmartSpectra stream for the film: a heart that drifts toward
/// [target] BPM with its waveform, the SDK's 12 s pulse average arriving
/// late, blinks, talking and expressions. Same shape as `World` in
/// test/world.dart.
class FilmPresage extends FakePresage {
  late Film film;
  bool running = false;
  String code = 'OK';
  String hint = '';

  /// Where the heart is heading; it gets there over a few seconds.
  double target = 72;
  double _bpm = 72;
  Map<String, double> expr = const {'neutral': 0.8};

  /// Average time between blinks.
  int blinkEveryMs = 3600;
  bool talking = false;

  final _rnd = math.Random(11);
  final _wave = PulseWaveGen(noise: 0.03);
  final List<(double, double)> _heartLog = [];
  final List<Map<String, Object?>> _pending = [];
  double? _waveAt;
  int? _pulseAt;
  int? _startedAt;
  int _nextBlink = 0;
  double _pulse = 72;
  Timer? _timer;

  int get now => clock.now().millisecondsSinceEpoch;

  void begin() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _emit());
  }

  void end() => _timer?.cancel();

  void talk(bool on) {
    if (on != talking) {
      _pending.add({'e': on ? 'talkStart' : 'talkEnd', 't': now});
    }
    talking = on;
  }

  /// The heart is at [bpm] right now (a new player sits down).
  void settle(double bpm) {
    target = bpm;
    _bpm = bpm;
    _pulse = bpm;
    _heartLog.clear();
  }

  void _emit() {
    if (!running) {
      _waveAt = null;
      return;
    }
    final t = now;
    const dt = 1000 / 30;
    const latency = 150;
    final trace = <double>[];
    final traceTs = <int>[];
    var at = _waveAt ?? (t - latency).toDouble();
    while (at <= t - latency) {
      _bpm += (target - _bpm) * (dt / 2200);
      final bpm = _bpm + 1.1 * math.sin(at / 2900);
      trace.add(_wave.next(at, bpm, dt));
      traceTs.add((at * 1000).round());
      _heartLog.add((at, bpm));
      at += dt;
    }
    _waveAt = at;
    // The SDK's pulse: a 12 s average that arrives 2 s late.
    _heartLog.removeWhere((e) => e.$1 < t - 14000);
    final window = [
      for (final (at, bpm) in _heartLog)
        if (at <= t - 2000) bpm,
    ];
    if (window.isNotEmpty) {
      _pulse = window.reduce((a, b) => a + b) / window.length;
    }
    if (_pulseAt == null || t - _pulseAt! >= 1000) _pulseAt = t;
    final started = _startedAt;
    final warm = started == null || t - started >= 12000;
    if (t >= _nextBlink) {
      _pending.add({'e': 'blinkEvent', 't': t});
      film.hotSeat?.blinkUntil = t + 150;
      _nextBlink =
          t + (blinkEveryMs * (0.55 + 0.9 * _rnd.nextDouble())).round();
    }
    controller.add(
      PresageSample.fromMap({
        't': t,
        'status': 'running',
        'pulse': _pulse,
        'pulseConf': warm ? 0.92 : 0.2,
        'pulseAt': _pulseAt,
        'expr': expr,
        'exprAt': t,
        'frameAt': t,
        'validation': {'code': code, 'hint': code == 'OK' ? '' : hint},
        'talking': talking,
        'events': List.of(_pending),
        if (trace.isNotEmpty) ...{
          'trace': trace,
          'traceTs': traceTs,
          'traceConf': [for (final _ in trace) 0.9],
        },
      }),
    );
    _pending.clear();
  }

  @override
  Future<void> start() async {
    await super.start();
    running = true;
    _startedAt = now;
  }

  @override
  Future<void> stop() async {
    await super.stop();
    running = false;
  }

  @override
  Future<void> reset() async {
    await super.reset();
    running = false;
  }

  /// Signing in takes a moment, as on a phone.
  @override
  Future<ConnectionTestResult> testConnection({required bool telemetry}) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    return super.testConnection(telemetry: telemetry);
  }
}

class _Say {
  _Say(this.text);

  final String text;
  final done = Completer<void>();
  bool started = false;
  bool unfilmed = false;
  AudioEvent? event;
  Line? line;
  Timer? timer;
}

/// The host: lines take as long as the voice takes to say them (so the game
/// waits as it does on a phone), and every line and sound is logged for the
/// soundtrack. Lines queue, like the native synthesizer's.
class FilmHost implements HostAudio {
  FilmHost(this.film);

  final Film film;
  final List<_Say> _queue = [];
  final List<String> said = [];

  static int _estimate(String text) => 350 + 62 * text.length;

  /// Nothing being said or waiting to be.
  bool get idle => _queue.isEmpty;

  /// The film is rolling again: a line that began in the skipped stretch
  /// and isn't over starts from the top, so it's heard whole.
  void restartLine() {
    if (_queue.isEmpty) return;
    final s = _queue.first;
    if (!s.started || !s.unfilmed) return;
    s.timer?.cancel();
    s.started = false;
  }

  @override
  Future<void> say(String text) {
    final s = _Say(text);
    _queue.add(s);
    said.add(text);
    return s.done.future;
  }

  @override
  Future<void> stopSpeaking() async {
    for (final s in _queue) {
      final e = s.event;
      if (e != null && e.startMs + e.durMs > film.videoMs) {
        e.cutMs = film.videoMs - e.startMs;
      }
      if (identical(film.hostLine, s.line)) film.hostLine = null;
      s.timer?.cancel();
      if (!s.done.isCompleted) s.done.complete();
    }
    _queue.clear();
  }

  /// The film jumped ahead: what the host was saying isn't on screen.
  void cutCaptions() => film.hostLine = null;

  /// Starts the next queued line. Called between frames, where the voice
  /// can be synthesized (real work, outside fake time).
  Future<void> service() async {
    if (_queue.isEmpty || _queue.first.started) return;
    final s = _queue.first
      ..started = true
      ..unfilmed = !film.recording;
    var ms = _estimate(s.text);
    if (film.recording) {
      final file = await _voice(s.text);
      if (file != null) {
        ms = wavMs(file) + 150;
        s.event = AudioEvent(file.path, film.videoMs, ms);
        film.audio.add(s.event!);
      }
      film.shot?.lines.add('Host: “${s.text}”');
    }
    final line = s.line = Line('Host', s.text, film.now, ms);
    film.hostLine = line;
    film.lastLine = line;
    s.timer = Timer(Duration(milliseconds: ms), () {
      if (identical(film.hostLine, line)) film.hostLine = null;
      _queue.remove(s);
      if (!s.done.isCompleted) s.done.complete();
    });
  }

  Future<File?> _voice(String text) async {
    final piper = Film.piper;
    if (piper == null) return null;
    final dir = Directory('${Film.outDir}/voice')..createSync(recursive: true);
    final spoken = text.replaceAll('…', '...').replaceAll('Hmm...', 'Hmmm.');
    final hash = spoken.codeUnits
        .fold<int>(0x811c9dc5, (h, c) => ((h ^ c) * 0x01000193) & 0xffffffff)
        .toRadixString(16);
    final file = File('${dir.path}/$hash.wav');
    if (!file.existsSync()) {
      await film.tester.runAsync(() async {
        final p = await Process.start('bash', [
          '-c',
          '$piper -f "${file.path}"',
        ]);
        unawaited(p.stdout.drain<void>());
        unawaited(p.stderr.drain<void>());
        p.stdin.writeln(spoken);
        await p.stdin.close();
        await p.exitCode;
      });
    }
    return file.existsSync() ? file : null;
  }

  @override
  Future<void> play(Sfx sfx) {
    final file = File('assets/sfx/${sfx.fileName}.wav');
    final ms = wavMs(file);
    if (film.rendering) {
      film.audio.add(
        AudioEvent(
          file.path,
          film.videoMs,
          ms,
          gain: 0.7,
          clockMs: film.now,
          unfilmed: !film.recording,
        ),
      );
    }
    final done = Completer<void>();
    Timer(Duration(milliseconds: ms), done.complete);
    return done.future;
  }
}

/// Length of a PCM WAV file, from its header.
int wavMs(File file) {
  final b = file.readAsBytesSync();
  final d = ByteData.sublistView(b);
  var byteRate = 0;
  var i = 12;
  while (i + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(i, i + 4));
    final len = d.getUint32(i + 4, Endian.little);
    if (id == 'fmt ') byteRate = d.getUint32(i + 16, Endian.little);
    if (id == 'data' && byteRate > 0) {
      final bytes = math.min(len, b.length - i - 8);
      return (bytes * 1000 / byteRate).round();
    }
    i += 8 + len + (len & 1);
  }
  return 1000;
}
