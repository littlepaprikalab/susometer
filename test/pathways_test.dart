// User pathways through the real screens at 390×844, with Flutter's
// accessibility guidelines checked on every screen visited: 44 pt tap
// targets (iOS), labelled tap targets, and WCAG text contrast measured on
// the rendered pixels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/settings/app_settings.dart';

import 'rig.dart';

/// Screens already checked in this test run (each phase checked once).
final _checked = <String>{};

Future<void> checkScreen(WidgetTester tester, String name) async {
  if (!_checked.add(name)) return;
  final handle = tester.ensureSemantics();
  await expectLater(
    tester,
    meetsGuideline(iOSTapTargetGuideline),
    reason: '$name: tap targets',
  );
  await expectLater(
    tester,
    meetsGuideline(labeledTapTargetGuideline),
    reason: '$name: labels',
  );
  await expectLater(
    tester,
    meetsGuideline(textContrastGuideline),
    reason: '$name: contrast',
  );
  handle.dispose();
}

extension on Rig {
  Future<void> startParty(List<String> names, {int questions = 3}) async {
    presage.storedKey = 'k';
    for (final n in names) {
      await addPlayer(n);
    }
    if (questions != 5) await tap('$questions');
    await tap('Start the show');
    await wait(300);
    if (game.phase == GamePhase.howToPlay) await tap("Got it, let's play");
  }
}

void main() {
  testWidgets('solo game, start to finish, with no Call it! or lie detector', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await checkScreen(tester, 'lobby');
    await rig.tap('Solo · host asks');
    await rig.tap('Spicy');
    rig.presage.storedKey = 'k';
    await rig.addPlayer('Sam');
    await rig.tap('3');
    await rig.tap('Start the show');
    await rig.wait(300);
    await checkScreen(tester, 'howToPlay');
    await rig.tap("Got it, let's play");
    await checkScreen(tester, 'consent');
    await rig.tap('I agree, measure me');
    await rig.wait(1500);
    await checkScreen(tester, 'calibrate');
    await rig.until(
      () => rig.game.phase == GamePhase.answer,
      what: 'host reads the question',
    );
    expect(find.text('The host asked'), findsOneWidget);
    expect(find.textContaining(rig.game.questionText), findsWidgets);
    await checkScreen(tester, 'answer-solo');
    for (var q = 0; q < 3; q++) {
      await rig.until(() => rig.game.phase == GamePhase.answer);
      rig.presage.talk(true);
      await rig.wait(1500);
      rig.presage.talk(false);
      await rig.wait(600);
      await rig.tap('Final answer');
      await rig.until(
        () => rig.game.phase == GamePhase.countdown,
        what: 'straight to countdown',
      );
      await checkScreen(tester, 'countdown');
      await rig.until(() => rig.game.phase == GamePhase.verdict);
      await checkScreen(tester, 'verdict');
      expect(find.textContaining('How the room called it'), findsNothing);
      await rig.tap(q < 2 ? 'Next question' : 'See the winners');
      await rig.wait(300);
    }
    expect(find.text('And the winners are…'), findsOneWidget);
    expect(find.text('Best lie detector'), findsNothing);
    await checkScreen(tester, 'leaderboard');
    await rig.tap('Watch the replay');
    await rig.wait(200);
    await checkScreen(tester, 'replay');
    await rig.tap('Wipe everything');
    await rig.wait(300);
    expect(find.text('Start the show'), findsOneWidget);
    expect(find.text('Sam'), findsNothing, reason: 'Wipe clears names too');
    await rig.finish();
  });

  testWidgets('everyone skips: no winners, no fake scores, then play again', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.tap('Skip my turn');
    await rig.wait(700);
    expect(find.text('Contestant 2 of 2'), findsOneWidget);
    await rig.tap('Skip my turn');
    await rig.wait(300);
    expect(find.textContaining('No clean reads this game'), findsOneWidget);
    expect(find.text('Share results'), findsOneWidget);
    await rig.tap('Play again');
    await rig.wait(300);
    expect(find.text('Sam'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('consent back: lobby on the first player, End the show later', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex'], questions: 3);
    await tester.tap(find.byTooltip('Back to lobby').first);
    await rig.wait(300);
    expect(
      find.text('Start the show'),
      findsOneWidget,
      reason: 'nothing played yet',
    );

    await rig.tap('Start the show');
    await rig.wait(300);
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.ask);
    rig.game.doneAsking();
    await rig.wait(200);
    await rig.tap('Final answer');
    await rig.until(
      () =>
          rig.game.phase == GamePhase.callIt ||
          rig.game.phase == GamePhase.redo,
    );
    if (rig.game.phase == GamePhase.callIt) {
      await checkScreen(tester, 'callIt');
      await rig.tap('Reveal');
      await rig.until(() => rig.game.phase == GamePhase.verdict);
      await rig.tap('End turn');
    } else {
      await rig.tap('Skip it');
    }
    await rig.until(
      () =>
          rig.game.phase == GamePhase.consent ||
          rig.game.phase == GamePhase.ask,
    );
    if (rig.game.phase == GamePhase.ask) {
      // Skip it moved to question 2; end Sam's turn from Pause instead.
      await tester.tap(find.bySemanticsLabel('Pause the game'));
      await rig.wait(200);
      await rig.tap('End the show');
      await rig.wait(200);
      expect(find.text('End the show?'), findsOneWidget);
      await checkScreen(tester, 'endShow');
      await rig.tap('Keep playing');
      await rig.wait(200);
      await rig.tap('Resume');
      await rig.wait(200);
    } else {
      await tester.tap(find.byTooltip('Back to lobby').first);
      await rig.wait(300);
      expect(
        find.text('End the show?'),
        findsOneWidget,
        reason: 'a question was played',
      );
      await rig.tap('End and see scores');
      await rig.wait(500);
      expect(find.text('And the winners are…'), findsOneWidget);
    }
    await rig.finish();
  });

  testWidgets('lobby limits and the Proof Panel shortcut', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    for (var i = 0; i < 9; i++) {
      await rig.addPlayer('Player$i');
    }
    expect(rig.game.players.length, 8);
    expect(find.text('Eight is the max'), findsOneWidget);
    // Five taps on the logo toggles the Proof Panel.
    await tester.ensureVisible(find.text('Sus-o-meter').first);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Sus-o-meter').first);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(rig.services.settings.proofPanel, isTrue);
    expect(find.text('Proof panel on.'), findsOneWidget);
    // Remove a player.
    await tester.tap(find.byTooltip('Remove Player0'));
    await tester.pump();
    expect(rig.game.players.length, 7);
    await rig.finish();
  });

  testWidgets(
    'calibration: Doesn\'t apply skips a warm-up; Proof Panel shows raw values',
    (tester) async {
      final rig = Rig(tester);
      await rig.pumpApp();
      rig.services.settings.proofPanel = true;
      await rig.startParty(['Sam', 'Alex']);
      await rig.tap('I agree, measure me');
      await rig.wait(1000);
      expect(find.text('PROOF PANEL · raw SmartSpectra'), findsOneWidget);
      expect(find.textContaining('telemetry off'), findsOneWidget);
      await rig.until(
        () => rig.game.currentWarmup != null,
        what: 'first warm-up',
      );
      final first = rig.game.currentWarmup!;
      await rig.tap("Doesn't apply? Next one");
      expect(first.skipped, isTrue);
      await rig.until(() => rig.game.phase == GamePhase.ask);
      expect(find.textContaining('tQ0'), findsOneWidget);
      await rig.finish();
    },
  );

  testWidgets('no clean read → Skip it moves on; backgrounding pauses', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex'], questions: 3);
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.ask);
    await checkScreen(tester, 'ask');
    rig.game.doneAsking();
    rig.presage.code = 'NO_FACE_FOUND';
    await rig.wait(2000);
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.redo);
    await checkScreen(tester, 'redo');
    rig.presage.code = 'OK';
    await rig.tap('Skip it');
    await rig.wait(300);
    expect(rig.game.questionIndex, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await rig.wait(300);
    expect(rig.game.paused, isTrue);
    expect(
      rig.presage.running,
      isFalse,
      reason: 'camera stops in the background',
    );
    // Frames only render once the app is back in the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await rig.wait(300);
    expect(find.text('Paused'), findsOneWidget);
    await rig.tap('Resume');
    await rig.wait(500);
    expect(rig.presage.running, isTrue);
    expect(rig.game.phase, GamePhase.ask);
    await rig.finish();
  });

  testWidgets('E5 → Presage key settings → back → Try again', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    rig.presage.startError = const PresageException(
      'authenticationFailed',
      'Invalid key',
    );
    await rig.tap('I agree, measure me');
    await rig.wait(300);
    expect(
      find.text('authenticationFailed · session not started'),
      findsOneWidget,
    );
    expect(
      find.text(describePresageCode('authenticationFailed', '')),
      findsOneWidget,
    );
    expect(
      find.text('Open Presage key settings below'),
      findsOneWidget,
      reason: 'a rejected key gets key steps, not Wi-Fi steps',
    );
    expect(find.text('Check Wi-Fi or cellular data is on'), findsNothing);
    await checkScreen(tester, 'sdkOffline');
    await rig.tap('Open Presage key settings');
    await rig.wait(500);
    expect(find.text('Settings'), findsOneWidget);
    await checkScreen(tester, 'settings');
    await tester.tap(find.byTooltip('Back to lobby').first);
    await rig.wait(500);
    expect(find.text("The meter won't warm up"), findsOneWidget);
    rig.presage.startError = null;
    await rig.tap('Try again');
    await rig.wait(500);
    expect(rig.game.phase, GamePhase.calibrate);
    await rig.finish();
  });

  testWidgets('E2 with the camera denied only offers Settings or the lobby', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    rig.device.camera = 'denied';
    await rig.startParty(['Sam', 'Alex']);
    expect(find.text('The show needs eyes and ears'), findsOneWidget);
    expect(find.text('Play without voice'), findsNothing);
    await checkScreen(tester, 'permissions');
    await rig.tap('Open Settings');
    expect(rig.device.calls, contains('openAppSettings'));
    await rig.tap('Back to lobby');
    await rig.wait(300);
    expect(find.text('Start the show'), findsOneWidget);
    await rig.finish();
  });
}
