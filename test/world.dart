import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/audio/host_audio.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/settings/app_settings.dart';
import 'package:susometer/voice/speech_service.dart';
import 'package:susometer/voice/turn_detector.dart';

import 'fakes.dart';
import 'synthetic.dart';

/// Records which phase each haptic fired in.
class PhaseHaptics implements HapticsApi {
  PhaseHaptics(this.phase);

  final GamePhase Function() phase;
  final List<(HapticCue, GamePhase)> cues = [];

  @override
  Future<void> cue(HapticCue cue) async => cues.add((cue, phase()));
}

/// A scripted SmartSpectra + speech world running on fake time.
class World {
  World(
    this.async, {
    TurnConfig turnConfig = const TurnConfig(
      autoQuestionEnd: false,
      autoAnswerEnd: false,
    ),
  }) {
    presage = RunningPresage(this);
    game = GameController(
      presage: presage,
      speech: speech,
      device: device,
      settings: settings,
      apiKey: ApiKeyController(presage),
      host: host,
      haptics: haptics = PhaseHaptics(() => game.phase),
      decks: DeckLibrary.fallback,
      turnConfig: turnConfig,
      now: () => now,
    );
    _emitter = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _emit(),
    );
  }

  final FakeAsync async;
  late final RunningPresage presage;
  final speech = FakeSpeech();
  final device = FakeDevice();
  final host = FakeHostAudio();
  final settings = AppSettings();
  late final PhaseHaptics haptics;
  late final GameController game;
  late final Timer _emitter;

  static const base = 1700000000000;
  int get now => base + async.elapsed.inMilliseconds;

  // Script knobs.
  bool running = false;
  bool emitting = true;
  String status = 'running';
  double pulse = 70;
  String code = 'OK';

  /// The camera stops delivering frames while the SDK still says it's
  /// running: snapshots keep coming with the last frame's time. Like the
  /// bridge, a new session's frame time starts when it starts running.
  bool cameraFrozen = false;
  int? _frameAt;

  /// Expression scores in every snapshot, fresh each time (like the SDK
  /// publishing a new expression sample every frame).
  Map<String, double> expr = const {'neutral': 0.8, 'surprise': 0.05};
  bool autoAnswerWarmups = true;

  /// Time to the next blink (ms), asked after each one. Every 4 s unless a
  /// test says otherwise (e.g. fewer while sitting still than chatting).
  int Function() blinkEveryMs = () => 4000;

  /// Pulse waveform (SPEC.md decision 63). When [heart] is set, each
  /// snapshot carries the waveform since the last one, beating at
  /// `heart(t)` BPM, and the SDK pulse becomes the mean heart rate over 12 s
  /// ending [sdkLagMs] ago (a 12 s average that also arrives late, as the
  /// real SDK's may), instead of [pulse].
  double Function(int t)? heart;
  int sdkLagMs = 2000;

  /// Waveform samples reach the bridge this late, plus up to
  /// [waveLatencyJitterMs] more, varying snapshot to snapshot.
  int waveLatencyMs = 150;
  int waveLatencyJitterMs = 120;
  final Random _latencyJitter = Random(7);

  /// Fuzzing: when set, some waveform batches are mangled the ways a
  /// misbehaving SDK or bridge could (SDK clock jumps either way, samples
  /// reversed or repeated, timestamps of the wrong length).
  Random? waveChaos;
  int _sdkShiftUs = 0;
  List<double> _lastTrace = const [];
  List<int> _lastTraceTs = const [];
  final PulseWaveGen _wave = PulseWaveGen();
  double? _waveAt;
  final List<(double, double)> _heartLog = [];
  final List<Map<String, Object?>> _pendingEvents = [];
  int? _pulseAt;
  int _nextBlink = 0;
  Warmup? _answered;

  /// Like the Swift bridge: an edge only when the state changes, and the
  /// current state in every snapshot.
  bool talking = false;
  void talk(bool on) {
    if (on != talking) {
      _pendingEvents.add({'e': on ? 'talkStart' : 'talkEnd', 't': now});
    }
    talking = on;
  }

  void say(String text, {bool isFinal = false}) => speech.controller.add(
    SpeechText(text: text, segment: speech.segment, isFinal: isFinal, tMs: now),
  );

  void _emit() {
    if (!running || !emitting) {
      _waveAt = null;
      return;
    }
    final t = now;
    final trace = <double>[];
    final traceTs = <int>[];
    final h = heart;
    if (h != null) {
      const dt = 1000 / 30;
      final latency =
          waveLatencyMs + _latencyJitter.nextInt(waveLatencyJitterMs + 1);
      var at = _waveAt ?? (t - latency).toDouble();
      while (at <= t - latency) {
        final bpm = h(at.round());
        trace.add(_wave.next(at, bpm, dt));
        traceTs.add((at * 1000).round());
        _heartLog.add((at, bpm));
        at += dt;
      }
      _waveAt = at;
      final r = waveChaos;
      if (r != null) {
        switch (r.nextInt(25)) {
          case 0:
            _sdkShiftUs -= r.nextInt(30000) * 1000;
          case 1:
            _sdkShiftUs += r.nextInt(30000) * 1000;
          case 2:
            final rt = trace.reversed.toList();
            final rts = traceTs.reversed.toList();
            trace
              ..clear()
              ..addAll(rt);
            traceTs
              ..clear()
              ..addAll(rts);
          case 3:
            trace.insertAll(0, _lastTrace);
            traceTs.insertAll(0, _lastTraceTs);
          case 4:
            traceTs.add(0);
        }
        for (var i = 0; i < traceTs.length; i++) {
          traceTs[i] += _sdkShiftUs;
        }
        _lastTrace = List.of(trace);
        _lastTraceTs = List.of(traceTs);
      }
      _heartLog.removeWhere((e) => e.$1 < t - sdkLagMs - 12000);
      final window = [
        for (final (at, bpm) in _heartLog)
          if (at <= t - sdkLagMs) bpm,
      ];
      if (window.isNotEmpty) {
        pulse = window.reduce((a, b) => a + b) / window.length;
      }
    }
    if (_pulseAt == null || t - _pulseAt! >= 1000) _pulseAt = t;
    if (!cameraFrozen || _frameAt == null) _frameAt = t;
    if (t >= _nextBlink) {
      _pendingEvents.add({'e': 'blinkEvent', 't': t});
      _nextBlink = t + blinkEveryMs();
    }
    // Answer each warm-up: start talking 0.8 s after it's asked, stop 2 s later.
    final w = game.currentWarmup;
    if (autoAnswerWarmups &&
        w != null &&
        !identical(w, _answered) &&
        t - w.askedAtMs >= 800) {
      _answered = w;
      talk(true);
      Timer(const Duration(seconds: 2), () => talk(false));
    }
    presage.controller.add(
      PresageSample.fromMap({
        't': t,
        'status': status,
        'pulse': pulse,
        'pulseConf': 0.9,
        'pulseAt': _pulseAt,
        'expr': expr,
        'exprAt': expr.isEmpty ? null : t,
        'frameAt': _frameAt,
        'validation': {'code': code, 'hint': code == 'OK' ? '' : 'hint'},
        'talking': talking,
        'events': List.of(_pendingEvents),
        if (trace.isNotEmpty) ...{
          'trace': trace,
          'traceTs': traceTs,
          'traceConf': [for (final _ in trace) 0.9],
        },
      }),
    );
    _pendingEvents.clear();
  }

  /// Advances fake time in 100 ms steps until [cond] holds.
  void until(
    bool Function() cond, {
    int maxMs = 120000,
    String? what,
    void Function()? step,
  }) {
    var waited = 0;
    while (!cond()) {
      step?.call();
      async.elapse(const Duration(milliseconds: 100));
      waited += 100;
      if (waited > maxMs) {
        fail(
          'Timed out waiting for ${what ?? 'condition'} (phase ${game.phase})',
        );
      }
    }
  }

  void elapse(int ms) => async.elapse(Duration(milliseconds: ms));

  void dispose() {
    _emitter.cancel();
    game.dispose();
  }

  /// Lobby → consent of the first player.
  void startGame(List<String> names, {int questions = 3}) {
    for (final n in names) {
      game.addPlayer(n);
    }
    game.setQuestionsPerTurn(questions);
    presage.storedKey = 'pk_test_1234';
    game.startShow();
    elapse(100);
    if (game.phase == GamePhase.howToPlay) game.dismissHowToPlay();
    expect(game.phase, GamePhase.consent);
  }

  /// Consent → calibrated and asking question 1.
  void calibrate() {
    game.agreeToMeasure();
    elapse(100);
    expect(game.phase, GamePhase.calibrate);
    until(
      () => game.phase == GamePhase.ask || game.phase == GamePhase.answer,
      what: 'calibration to finish',
    );
  }

  /// Party question with tap-to-advance; returns the result.
  QuestionResult askAndAnswer({
    String question = 'Have you ever re-gifted a present?',
    String answer = 'No way. Okay, maybe once.',
    double answerPulse = 70,
    List<String> votesSus = const [],
  }) {
    expect(game.phase, GamePhase.ask);
    elapse(300);
    say(question);
    elapse(1500);
    game.doneAsking();
    expect(game.phase, GamePhase.answer);
    elapse(200);
    pulse = answerPulse;
    elapse(1100);
    talk(true);
    elapse(300);
    say(answer);
    elapse(2500);
    talk(false);
    elapse(800);
    game.finalAnswer();
    expect(game.phase, GamePhase.settle);
    until(() => game.phase != GamePhase.settle, what: 'settle');
    pulse = 70;
    if (game.phase == GamePhase.callIt) {
      for (final id in votesSus) {
        game.cycleVote(id);
        game.cycleVote(id);
      }
      game.reveal();
    }
    expect(game.phase, GamePhase.countdown);
    until(() => game.phase == GamePhase.verdict, what: 'countdown');
    return game.currentResult!;
  }
}

class RunningPresage extends FakePresage {
  RunningPresage(this.world);

  final World world;

  @override
  Future<void> start() async {
    await super.start();
    world.running = true;
    world._frameAt = null;
  }

  @override
  Future<void> stop() async {
    await super.stop();
    world.running = false;
    world._frameAt = null;
  }

  @override
  Future<void> reset() async {
    await super.reset();
    world.running = false;
    world._frameAt = null;
  }
}
