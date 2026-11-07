import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game_root.dart';
import 'package:susometer/app_scope.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/main.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/voice/speech_service.dart';
import 'package:susometer/voice/turn_detector.dart';

import 'fakes.dart';

/// Fake SmartSpectra that streams snapshots while "running".
class StreamingPresage extends FakePresage {
  bool running = false;
  bool emitting = true;
  double pulse = 70;
  String code = 'OK';

  /// Like the real SDK (and `World`): after each start, the pulse comes
  /// with too little confidence to count for this long.
  int pulseWarmupMs = 12000;
  int? _startedAt;

  /// Expression scores in every snapshot (none unless a test sets them).
  Map<String, double> expr = const {};
  final List<Map<String, Object?>> pending = [];
  int? _pulseAt;
  int _nextBlink = 0;
  Timer? _timer;

  void begin() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _emit());
  }

  void end() => _timer?.cancel();

  int get now => clock.now().millisecondsSinceEpoch;

  /// Like the Swift bridge: an edge only when the state changes, and the
  /// current state in every snapshot.
  bool talking = false;
  void talk(bool on) {
    if (on != talking) {
      pending.add({'e': on ? 'talkStart' : 'talkEnd', 't': now});
    }
    talking = on;
  }

  void _emit() {
    if (!running || !emitting) return;
    final t = now;
    if (_pulseAt == null || t - _pulseAt! >= 1000) _pulseAt = t;
    final started = _startedAt;
    final warm = started == null || t - started >= pulseWarmupMs;
    if (t >= _nextBlink) {
      pending.add({'e': 'blinkEvent', 't': t});
      _nextBlink = t + 4000;
    }
    controller.add(
      PresageSample.fromMap({
        't': t,
        'status': 'running',
        'pulse': pulse,
        'pulseConf': warm ? 0.9 : 0.2,
        'pulseAt': _pulseAt,
        'validation': {'code': code, 'hint': ''},
        'talking': talking,
        'expr': expr,
        'exprAt': expr.isEmpty ? null : t,
        'frameAt': t,
        'events': List.of(pending),
      }),
    );
    pending.clear();
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
}

class Rig {
  Rig(this.tester);

  final WidgetTester tester;
  final presage = StreamingPresage();
  final speech = FakeSpeech();
  final device = FakeDevice();
  final host = FakeHostAudio();
  late AppServices services;
  Warmup? _answered;
  int? _nextWarmupAt;

  /// [until] taps like a player through calibration, which never moves on
  /// by itself: Next 1.5 s after each warm-up answer, and Start the
  /// questions once the normal is locked in (calling the controller, as the
  /// buttons do). Off: the test taps the buttons.
  bool autoTaps = true;

  GameController get game => services.game;

  Future<void> pumpApp({
    TurnConfig turnConfig = const TurnConfig(),
    Size size = const Size(390, 844),
  }) async {
    useRealPhone(tester, size);
    services = AppServices(
      presage: presage,
      speech: speech,
      device: device,
      host: host,
      haptics: FakeHaptics(),
      turnConfig: turnConfig,
    );
    presage.begin();
    await tester.pumpWidget(SusApp(services: services));
    await tester.pump();
  }

  /// Pumps 100 ms frames until [cond], answering warm-ups along the way.
  Future<void> until(
    bool Function() cond, {
    int maxMs = 90000,
    String? what,
  }) async {
    var waited = 0;
    while (!cond()) {
      final w = game.currentWarmup;
      if (w != null &&
          !identical(w, _answered) &&
          presage.now - w.askedAtMs >= 800) {
        _answered = w;
        presage.talk(true);
        _nextWarmupAt = presage.now + 3500;
        Timer(const Duration(seconds: 2), () => presage.talk(false));
      }
      if (autoTaps && game.phase == GamePhase.calibrate) {
        final next = _nextWarmupAt;
        if (w != null &&
            identical(w, _answered) &&
            next != null &&
            presage.now >= next) {
          _nextWarmupAt = null;
          game.nextWarmup();
        }
        if (game.calibStage == CalibStage.ready) game.startQuestions();
      }
      await tester.pump(const Duration(milliseconds: 100));
      waited += 100;
      if (waited > maxMs) {
        fail(
          'Timed out waiting for ${what ?? 'condition'} (phase ${game.phase})',
        );
      }
    }
  }

  Future<void> tap(String text) async {
    await waitOutTapGuard(tester);
    final finder = find.text(text);
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> wait(int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Leaves the app for [ms] and comes back, the way Flutter reports it on
  /// iOS (a screenshot's full-screen preview on iOS 26 does the same).
  Future<void> leaveApp(int ms) async {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await wait(ms);
    // Frames only render once the app is back in the foreground.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await wait(300);
  }

  void say(String text) => speech.controller.add(
    SpeechText(
      text: text,
      segment: speech.segment,
      isFinal: false,
      tMs: presage.now,
    ),
  );

  Future<void> addPlayer(String name) async {
    await tester.enterText(find.byKey(const ValueKey('addContestant')), name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  Future<void> finish() async {
    presage.end();
    await tester.pumpWidget(const SizedBox());
    game.dispose();
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Waits until the post-phase-change tap guard (see game_root.dart) is off,
/// the way a person's next deliberate tap would.
Future<void> waitOutTapGuard(WidgetTester tester) async {
  bool guarded() {
    final f = find.byKey(phaseTapGuardKey);
    return f.evaluate().isNotEmpty && tester.widget<IgnorePointer>(f).ignoring;
  }

  for (var i = 0; i < 10 && guarded(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A real iPhone's screen in the test view: size, 3x pixels, and the safe
/// areas (status bar, home indicator) that real layouts lose. iPhone 14:
/// 47 pt top, 34 pt bottom. iPhone SE: 20 pt top, none at the bottom.
void useRealPhone(WidgetTester tester, Size size) {
  final notched = size.height >= 800;
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(
    top: (notched ? 47 : 20) * 3,
    bottom: (notched ? 34 : 0) * 3,
  );
  tester.view.viewPadding = tester.view.padding;
  addTearDown(tester.view.reset);
}
