import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/voice/speech_service.dart';

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
      expect(find.text('Alex, ask your question!'), findsOneWidget);
      rig.say('Have you ever told a fib number ${q + 1}?');
      await rig.wait(300);
      expect(
        find.text('Have you ever told a fib number ${q + 1}?'),
        findsOneWidget,
      );
      await rig.tap('Done asking');
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
      await rig.tap('Legit');
      expect(rig.game.pendingVotes.values, [Vote.legit]);
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
    // Play again asks first (decision 82): it wipes the game just played.
    await rig.tap('Play again');
    expect(find.text('Play again?'), findsOneWidget);
    await rig.tap('Wipe and play again');
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
    expect(find.text('Alex, ask your question!'), findsOneWidget);
    await rig.finish();
  });

  testWidgets(
    'coming back: the Pause sheet never flashes up for a short trip',
    (tester) async {
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
      final binding = tester.binding;
      void out() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }

      // On the way back in, iOS shows the app (inactive, frames on) a moment
      // before it's active, and only then does the game carry on.
      void backInView() {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      }

      out();
      await rig.wait(3000);
      backInView();
      await tester.pump();
      expect(
        find.text('Paused'),
        findsNothing,
        reason: 'the sheet flashed up just before the game carried on',
      );
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await rig.wait(300);
      expect(find.text('Paused'), findsNothing);
      expect(rig.presage.running, isTrue);

      // Away longer: the sheet is there as soon as the app is.
      out();
      await rig.wait(GameController.autoResumeWithinMs + 5000);
      backInView();
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await rig.wait(300);
      expect(find.text('Paused'), findsOneWidget);
      await rig.tap('Resume');
      await rig.wait(300);
      expect(rig.presage.running, isTrue);
      await rig.finish();
    },
  );

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
    await rig.tap('Ready to answer');
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

  testWidgets('nothing on screen moves on by itself (decision 76)', (
    tester,
  ) async {
    final rig = Rig(tester)..autoTaps = false;
    await rig.pumpApp();
    rig.presage.storedKey = 'k';
    rig.game.hasSeenHowToPlay = true;
    await rig.addPlayer('Sam');
    await rig.addPlayer('Alex');
    await rig.tap('Start the show');
    await rig.wait(300);
    await rig.tap('I agree, measure me');
    await rig.until(
      () => rig.game.calibStage == CalibStage.chat,
      what: 'warm-ups',
    );

    // Each warm-up waits for Next, then the questions wait for Start.
    expect(find.text('Answer out loud, then tap Next.'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      final warmup = rig.game.currentWarmup!;
      await rig.until(
        () => warmup.latencyS != null && !rig.presage.talking,
        what: 'warm-up ${i + 1} answered',
      );
      await rig.wait(5000);
      expect(identical(rig.game.currentWarmup, warmup), isTrue);
      await rig.tap('Next');
      await rig.wait(700);
    }
    await rig.until(
      () => rig.game.calibStage == CalibStage.ready,
      what: 'the normal locked in',
    );
    expect(find.text('Start the questions'), findsOneWidget);
    expect(find.text("That's your normal locked in."), findsOneWidget);
    await rig.wait(10000);
    expect(rig.game.phase, GamePhase.calibrate);
    await rig.tap('Start the questions');
    await rig.wait(300);

    // Ask: the host names the asker; a pause or a laugh moves nothing.
    expect(rig.game.phase, GamePhase.ask);
    expect(find.text('Alex, ask your question!'), findsOneWidget);
    expect(find.text('Sam: tap Done asking, then answer.'), findsOneWidget);
    expect(find.text('Too loud? Tap when done asking'), findsNothing);
    rig.say('Have you ever');
    final asked = rig.speech.segment;
    await rig.wait(500);
    rig.presage.talk(true);
    await rig.wait(600);
    rig.presage.talk(false);
    await rig.wait(1500);
    // Like the recognizer: a laugh may have opened a new segment (it might
    // have been the answer), which starts from the new words.
    rig.say(rig.speech.segment == asked ? 'Have you ever lied?' : 'lied?');
    await rig.wait(5000);
    expect(rig.game.phase, GamePhase.ask);
    await rig.tap('Done asking');
    expect(find.text('Q: “Have you ever lied?”'), findsOneWidget);
    expect(find.text("Tap when you're done"), findsOneWidget);

    // Answer: a long silence gets a nudge, not an ending.
    await rig.wait(21000);
    expect(rig.game.phase, GamePhase.answer);
    expect(
      find.text('No answer? Tap anyway, or Pause to skip'),
      findsOneWidget,
    );
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.callIt);

    // Call it!: no countdown to the reveal.
    expect(find.text('0 / 1 voted'), findsOneWidget);
    expect(find.textContaining('Reveal in'), findsNothing);
    await rig.wait(15000);
    expect(rig.game.phase, GamePhase.callIt);
    // Pick, change your mind, take it back, pick again (decision 77).
    final alex = rig.game.voters.single.id;
    await rig.tap('Legit');
    expect(find.text('1 / 1 voted'), findsOneWidget);
    expect(rig.game.pendingVotes[alex], Vote.legit);
    await rig.tap('Sus');
    expect(rig.game.pendingVotes[alex], Vote.sus);
    // A second tap on the same pick right away is a double tap: it stays.
    await rig.tap('Sus');
    expect(rig.game.pendingVotes[alex], Vote.sus);
    await rig.wait(700);
    await rig.tap('Sus');
    expect(find.text('0 / 1 voted'), findsOneWidget);
    expect(rig.game.pendingVotes, isEmpty);
    await rig.wait(700);
    await rig.tap('Sus');
    expect(find.text('1 / 1 voted'), findsOneWidget);
    await rig.tap('Reveal');
    expect(rig.game.currentResult!.votes[alex], Vote.sus);
    expect(rig.game.phase, GamePhase.countdown);
    await rig.finish();
  });
}
