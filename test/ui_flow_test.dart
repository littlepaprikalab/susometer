import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/voice/speech_service.dart';
import 'package:susometer/voice/turn_detector.dart';

import 'rig.dart';

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
    // Each row's pulse line carries its numbers: the normal and the peak.
    final first = rig.game.turns.first.results.first;
    final peak = first.pulseTrace.map((p) => p.$2).reduce(math.max).round();
    expect(find.text('normal ${first.basePulse!.round()}'), findsWidgets);
    expect(find.text('peak $peak BPM'), findsWidgets);
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
    await waitOutTapGuard(tester);
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

  testWidgets('leaving the app: the Pause sheet fits the phase', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    rig.presage.storedKey = 'k';
    rig.game.hasSeenHowToPlay = true;
    await rig.tap('Solo · host asks');
    await rig.addPlayer('Sam');
    await rig.tap('Start the show');
    await rig.wait(300);
    await rig.tap('I agree, measure me');
    await rig.wait(3000);
    expect(rig.game.phase, GamePhase.calibrate);

    // Calibration starts over: the camera stopped while the app was away.
    await rig.leaveApp(GameController.autoResumeWithinMs + 5000);
    expect(
      find.text(
        'You left the app, so the camera stopped. '
        'Calibration starts over when you resume.',
      ),
      findsOneWidget,
    );
    expect(find.text('Skip my turn'), findsOneWidget);
    await rig.tap('Resume');
    await rig.until(() => rig.game.phase == GamePhase.answer);
    rig.presage.talk(true);
    await rig.wait(1500);
    rig.presage.talk(false);
    await rig.wait(600);
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.verdict);

    // The verdict: nothing to restart or skip, it just waits.
    await rig.leaveApp(GameController.autoResumeWithinMs + 5000);
    expect(find.text('Paused'), findsOneWidget);
    expect(
      find.text(
        'You left the app, so the camera stopped. '
        'The game picks up where it left off.',
      ),
      findsOneWidget,
    );
    expect(find.text('Skip question'), findsNothing);
    expect(find.text('Skip my turn'), findsNothing);
    await rig.tap('Resume');
    await rig.wait(300);
    expect(find.text('Paused'), findsNothing);
    expect(rig.game.phase, GamePhase.verdict);

    // Pause tapped during a question: no "you left the app".
    await rig.tap('Next question');
    await rig.until(() => rig.game.phase == GamePhase.answer);
    await waitOutTapGuard(tester);
    await tester.tap(find.bySemanticsLabel('Pause the game'));
    await rig.wait(200);
    expect(
      find.text('The question starts over when you resume.'),
      findsOneWidget,
    );
    await rig.tap('Resume');
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
    expect(find.text('Hold still'), findsOneWidget, reason: 'E3 stamp');
    expect(find.text('Rest your elbows or prop the phone up.'), findsOneWidget);
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

  testWidgets('automatic mode: backup copy from the mocks', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp(turnConfig: const TurnConfig());
    rig.presage.storedKey = 'k';
    rig.game.hasSeenHowToPlay = true;
    await rig.addPlayer('Sam');
    await rig.addPlayer('Alex');
    await rig.tap('Start the show');
    await rig.wait(300);
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.ask);
    expect(find.text('Too loud? Tap when done asking'), findsOneWidget);
    expect(
      find.text("Sam: just start answering when you're ready."),
      findsOneWidget,
    );
    rig.say('Have you ever lied?');
    await rig.until(() => rig.game.phase == GamePhase.answer, maxMs: 4000);
    expect(find.text('Or it ends itself after 4s of silence'), findsOneWidget);
    expect(find.text('Q: “Have you ever lied?”'), findsOneWidget);
    await rig.finish();
  });
}
