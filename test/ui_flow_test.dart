import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  final List<Map<String, Object?>> pending = [];
  int? _pulseAt;
  int _nextBlink = 0;
  Timer? _timer;

  void begin() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _emit());
  }

  void end() => _timer?.cancel();

  int get now => clock.now().millisecondsSinceEpoch;

  void talk(bool on) =>
      pending.add({'e': on ? 'talkStart' : 'talkEnd', 't': now});

  void _emit() {
    if (!running || !emitting) return;
    final t = now;
    if (_pulseAt == null || t - _pulseAt! >= 1000) _pulseAt = t;
    if (t >= _nextBlink) {
      pending.add({'e': 'blinkEvent', 't': t});
      _nextBlink = t + 4000;
    }
    controller.add(
      PresageSample.fromMap({
        't': t,
        'status': 'running',
        'pulse': pulse,
        'pulseConf': 0.9,
        'pulseAt': _pulseAt,
        'validation': {'code': code, 'hint': ''},
        'events': List.of(pending),
      }),
    );
    pending.clear();
  }

  @override
  Future<void> start() async {
    await super.start();
    running = true;
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
  late final AppServices services;
  Warmup? _answered;

  GameController get game => services.game;

  Future<void> pumpApp({
    TurnConfig turnConfig = const TurnConfig(
      autoQuestionEnd: false,
      autoAnswerEnd: false,
    ),
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
        Timer(const Duration(seconds: 2), () => presage.talk(false));
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

void main() {
  testWidgets('first run: Start the show without a key opens Settings', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    expect(find.text('Sus-o-meter'), findsOneWidget);
    expect(
      find.text('For fun only. Measures stress reactions, not truth.'),
      findsOneWidget,
    );
    await rig.addPlayer('Sam');
    await rig.addPlayer('Alex');
    expect(find.text('Sam'), findsOneWidget);
    await rig.tap('Start the show');
    await rig.wait(500);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('No key yet'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('a whole party game through the screens', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    rig.presage.storedKey = 'pk_test_1234';
    await rig.addPlayer('Sam');
    await rig.addPlayer('Alex');
    await rig.tap('3');
    await rig.tap('Start the show');
    await rig.wait(300);

    expect(find.text('How to play'), findsOneWidget);
    await rig.tap("Got it, let's play");
    expect(find.text('Pass the phone to'), findsOneWidget);
    expect(find.text('Contestant 1 of 2'), findsOneWidget);
    expect(find.text('SDK telemetry is switched off'), findsOneWidget);
    await rig.tap('I agree, measure me');
    await rig.wait(300);
    expect(find.text('Warming up Sam'), findsOneWidget);
    await rig.until(() => rig.game.phase == GamePhase.ask, what: 'calibration');

    for (var q = 0; q < 3; q++) {
      expect(find.text('Ask your question!'), findsOneWidget);
      rig.say('Have you ever told a fib number ${q + 1}?');
      await rig.wait(300);
      expect(
        find.text('Have you ever told a fib number ${q + 1}?'),
        findsOneWidget,
      );
      await rig.tap('Tap when done asking');
      expect(find.text('Sam, your answer?'), findsOneWidget);
      rig.presage.talk(true);
      await rig.wait(400);
      rig.say('Never ever.');
      await rig.wait(1500);
      rig.presage.talk(false);
      await rig.wait(800);
      expect(find.textContaining('to start answering'), findsOneWidget);
      await rig.tap('Final answer');
      expect(find.text('Locking in the reading…'), findsOneWidget);
      await rig.until(
        () => rig.game.phase == GamePhase.callIt,
        what: 'Call it!',
      );
      expect(find.text('Call it!'), findsOneWidget);
      await rig.tap('Tap to vote');
      expect(find.text('Legit'), findsOneWidget);
      await rig.tap('Reveal');
      expect(find.text('The Sus-o-meter says…'), findsOneWidget);
      await rig.until(
        () => rig.game.phase == GamePhase.verdict,
        what: 'verdict',
      );
      expect(find.text('THE SUS-O-METER SAYS'), findsOneWidget);
      expect(find.textContaining('How the room called it'), findsOneWidget);
      if (q < 2) {
        await rig.tap('Next question');
        await rig.wait(200);
      }
    }
    await rig.tap('Next contestant');
    await rig.wait(500);
    expect(find.text('Contestant 2 of 2'), findsOneWidget);
    await rig.tap('Skip my turn');
    await rig.wait(500);
    expect(find.text('And the winners are…'), findsOneWidget);
    expect(find.text('Best poker face'), findsWidgets);
    await rig.tap('Share results');
    // Rendering the share image is real async work.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await rig.wait(200);
    expect(rig.device.shares, 1);
    await rig.tap('Watch the replay');
    await rig.wait(200);
    expect(find.text('The replay'), findsOneWidget);
    expect(find.textContaining('Never ever.'), findsWidgets);
    await rig.tap('Play again');
    await rig.wait(300);
    expect(find.text('Start the show'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('pause, then End the show from the sheet', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    rig.presage.storedKey = 'k';
    rig.game.hasSeenHowToPlay = true;
    await rig.addPlayer('Sam');
    await rig.addPlayer('Alex');
    await rig.tap('Start the show');
    await rig.wait(300);
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.ask);
    await tester.tap(find.bySemanticsLabel('Pause the game'));
    await rig.wait(200);
    expect(find.text('Paused'), findsOneWidget);
    await rig.tap('End the show');
    await rig.wait(200);
    expect(find.text('End the show?'), findsOneWidget);
    expect(find.text('Not played yet: Alex'), findsOneWidget);
    await rig.tap('Keep playing');
    await rig.wait(200);
    expect(find.text('End the show?'), findsNothing);
    expect(find.text('Paused'), findsOneWidget);
    await rig.tap('Resume');
    await rig.wait(300);
    expect(find.text('Ask your question!'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('E2, E4 and E5 screens render and lead somewhere', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    rig.presage.storedKey = 'k';
    rig.game.hasSeenHowToPlay = true;
    rig.speech.permissions = const SpeechPermissions(
      mic: 'denied',
      speech: 'authorized',
      onDevice: true,
    );
    await rig.addPlayer('Sam');
    await rig.addPlayer('Alex');
    await rig.tap('Start the show');
    await rig.wait(300);
    expect(find.text('The show needs eyes and ears'), findsOneWidget);
    await rig.tap('Play without voice');
    await rig.wait(200);
    expect(find.text('Pass the phone to'), findsOneWidget);

    rig.presage.startError = const PresageException('networkError', 'Offline');
    await rig.tap('I agree, measure me');
    await rig.wait(300);
    expect(find.text("The meter won't warm up"), findsOneWidget);
    expect(find.text('networkError · session not started'), findsOneWidget);
    rig.presage.startError = null;
    await rig.tap('Try again');
    await rig.until(() => rig.game.phase == GamePhase.ask);
    expect(
      find.text('Done asking'),
      findsOneWidget,
      reason: 'no-mic mode uses a solid button',
    );

    await rig.tap('Done asking');
    rig.presage.code = 'EXCESSIVE_MOTION';
    await rig.wait(2500);
    expect(find.text('Hold still'), findsOneWidget, reason: 'E3 banner');
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.redo);
    expect(find.text('No clean read'), findsOneWidget);
    expect(find.text('Sam moved around a lot while answering'), findsOneWidget);
    rig.presage.code = 'OK';
    await rig.tap('Ask it again');
    await rig.wait(200);
    expect(rig.game.phase, GamePhase.ask);
    await rig.finish();
  });
}
