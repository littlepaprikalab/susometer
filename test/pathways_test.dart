// User pathways through the real screens at 390×844, with Flutter's
// accessibility guidelines checked on every screen visited: 44 pt tap
// targets (iOS), labelled tap targets, and WCAG text contrast measured on
// the rendered pixels.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/presage/presage_models.dart';
import 'package:susometer/settings/app_settings.dart';
import 'package:susometer/theme/game_widgets.dart';

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

/// The face oval never runs under the camera's chips or cards: checks
/// points along the oval against each widget's box.
void expectOvalClear(WidgetTester tester, List<Finder> overlays, String when) {
  final video = tester.getRect(find.byType(CameraPreview));
  final clear = tester
      .widget<CameraWindow>(find.byType(CameraWindow))
      .guideClear;
  final oval = faceOvalRect(video.size, clear).shift(video.topLeft);
  expect(oval.height, greaterThan(60), reason: '$when: oval too small');
  for (final f in overlays) {
    for (final el in f.evaluate()) {
      final box = (el.renderObject! as RenderBox);
      final r = box.localToGlobal(Offset.zero) & box.size;
      for (var i = 0; i < 72; i++) {
        final a = i * math.pi / 36;
        final p =
            oval.center +
            Offset(math.cos(a) * oval.width / 2, math.sin(a) * oval.height / 2);
        expect(
          r.deflate(1).contains(p),
          isFalse,
          reason: '$when: the oval runs under $f',
        );
      }
    }
  }
}

DotChipFinder chip(String text) => find.ancestor(
  of: find.textContaining(text),
  matching: find.byType(DotChip),
);

typedef DotChipFinder = Finder;

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
    // The question stays on screen until Sam is ready.
    await rig.wait(3000);
    expect(find.text('Q: “${rig.game.questionText}”'), findsNothing);
    expect(find.text('Ready to answer'), findsOneWidget);
    await checkScreen(tester, 'ask-solo');
    await rig.tap('Ready to answer');
    await rig.wait(100);
    expect(find.text('Q: “${rig.game.questionText}”'), findsOneWidget);
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
      expect(
        find.bySemanticsLabel(RegExp('^Pulse through the question')),
        findsOneWidget,
      );
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
    await waitOutTapGuard(tester);
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
      await waitOutTapGuard(tester);
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
      await waitOutTapGuard(tester);
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
    expect(find.text("Picks up again when it's clear"), findsOneWidget);
    expectOvalClear(tester, [
      chip('Reading paused'),
      chip('Picks up again'),
    ], 'bad signal');
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
    await waitOutTapGuard(tester);
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

  // iPhone 14/15 and the smallest iOS 17 phone (iPhone SE, 375×667).
  for (final screen in const [Size(390, 844), Size(375, 667)]) {
    for (final scale in [1.0, 1.3]) {
      for (final mode in GameMode.values) {
        testWidgets(
          'the camera keeps its size, place and native view from Ask to Settle '
          '(${mode.name}, text ×$scale, ${screen.width.round()}×${screen.height.round()})',
          (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final rig = Rig(tester);
            await rig.pumpApp(size: screen);
            if (mode == GameMode.solo) {
              await rig.tap('Solo · host asks');
              // The fake host finishes instantly; with the voice off the host
              // "reads" for a few seconds, so Ask stays on screen.
              rig.services.settings.hostVoice = false;
            }
            await rig.startParty(
              mode == GameMode.solo ? ['Christopher'] : ['Christopher', 'Alex'],
            );
            await rig.tap('I agree, measure me');
            await rig.until(() => rig.game.phase == GamePhase.calibrate);
            await rig.wait(1500);
            expectOvalClear(tester, [
              chip('Face found'),
              chip('Looking for a face'),
              chip('Light'),
            ], 'calibrate');
            // During a warm-up answer the "is talking" chip shows too.
            await rig.until(
              () =>
                  rig.game.currentWarmup != null &&
                  (rig.game.live.sample?.talking ?? false),
              what: 'a warm-up answer',
            );
            await rig.wait(200);
            expect(find.textContaining('is talking'), findsOneWidget);
            expectOvalClear(tester, [
              chip('Face found'),
              chip('Light'),
              find.byType(LiveStatCard),
            ], 'calibrate, talking');
            await rig.until(() => rig.game.phase == GamePhase.ask);
            await rig.wait(200);

            final camera = find.byType(CameraPreview);
            final liveCards = find.ancestor(
              of: find.text('Pulse'),
              matching: find.byType(Container),
            );
            expectOvalClear(tester, [
              chip('Measuring'),
              liveCards.first,
            ], 'ask');
            final rect = tester.getRect(camera);
            final element = tester.element(camera);
            void same(String when) {
              expect(tester.getRect(camera), rect, reason: when);
              expect(
                identical(tester.element(camera), element),
                isTrue,
                reason: '$when: the camera view was rebuilt',
              );
            }

            expect(
              rect.height,
              greaterThan(screen.height > 700 ? 240 : 150),
              reason: 'the face stays big enough to frame',
            );
            if (mode == GameMode.party) {
              rig.say(
                'Have you ever told a friend you loved a gift they gave you and '
                'then quietly returned it to the store the very next day?',
              );
              await rig.wait(300);
              same('a long question');
              rig.game.doneAsking();
            }
            await rig.until(() => rig.game.phase == GamePhase.answer);
            await rig.wait(200);
            same('answer starts');
            if (mode == GameMode.solo) {
              // The question stays up until the player is ready.
              expect(find.text('Ready to answer'), findsOneWidget);
              expect(find.text('Final answer'), findsNothing);
              await rig.tap('Ready to answer');
              await rig.wait(100);
              same('ready to answer');
            }
            expect(find.text('Final answer'), findsOneWidget);
            rig.presage.talk(true);
            await rig.wait(1200);
            rig.say(
              'No way, absolutely not, I would never, okay maybe once but it '
              'was a really ugly sweater and honestly anyone would have done it',
            );
            await rig.wait(800);
            expect(find.textContaining('to start answering'), findsOneWidget);
            same('a long answer with the hesitation chip');
            expectOvalClear(tester, [
              chip('Measuring'),
              liveCards.first,
              find
                  .ancestor(
                    of: find.text('Blinks'),
                    matching: find.byType(Container),
                  )
                  .first,
            ], 'answer');
            rig.presage.talk(false);
            await rig.wait(400);
            await rig.tap('Final answer');
            await rig.wait(200);
            expect(rig.game.phase, GamePhase.settle);
            expect(find.text('Locking in the reading…'), findsOneWidget);
            same('settle');
            expect(find.bySemanticsLabel('Pause the game'), findsOneWidget);
            // The Proof Panel sits above the live cards, never over them.
            rig.services.settings.proofPanel = true;
            await rig.wait(200);
            final panel = tester.getRect(
              find
                  .ancestor(
                    of: find.text('PROOF PANEL · raw SmartSpectra'),
                    // The panel's own box (a Container's rect would include
                    // its margin).
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            );
            final cards = tester.getRect(
              find
                  .ancestor(
                    of: find.text('Pulse'),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            expect(
              panel.bottom,
              lessThanOrEqualTo(cards.top),
              reason: 'Proof Panel covers the live cards',
            );
            rig.services.settings.proofPanel = false;
            await rig.finish();
          },
        );
      }
    }
  }

  testWidgets('a double tap never carries into the next screen', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    rig.presage.storedKey = 'k';
    await rig.addPlayer('Sam');
    await rig.addPlayer('Alex');
    await rig.tap('Start the show');
    await rig.wait(300);

    Future<void> quickSecondTap(String first, String second) async {
      await waitOutTapGuard(tester);
      await tester.tap(find.text(first));
      // Two frames, 120 ms in all: a typical double tap's second touch.
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text(second), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
    }

    // "Got it" → "I agree" must not consent by accident.
    await quickSecondTap("Got it, let's play", 'I agree, measure me');
    expect(rig.game.phase, GamePhase.consent, reason: 'consent is deliberate');
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.ask);
    // "Tap when done asking" → "Final answer" must not end the answer
    // before it starts.
    await quickSecondTap('Tap when done asking', 'Final answer');
    expect(rig.game.phase, GamePhase.answer);
    await rig.wait(500);
    await rig.tap('Final answer');
    await rig.wait(100);
    expect(rig.game.phase, GamePhase.settle, reason: 'a deliberate tap works');
    await rig.finish();
  });

  testWidgets('solo: a double tap on Ready to answer never ends the answer', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.tap('Solo · host asks');
    await rig.startParty(['Sam']);
    await rig.tap('I agree, measure me');
    await rig.until(() => rig.game.phase == GamePhase.answer);
    await rig.wait(600);
    expect(rig.game.soloHoldsQuestion, isTrue);
    // Final answer appears where Ready to answer was, with no phase change.
    await waitOutTapGuard(tester);
    await tester.tap(find.text('Ready to answer'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Final answer'), findsOneWidget);
    await tester.tap(find.text('Final answer'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(rig.game.phase, GamePhase.answer, reason: 'second tap ignored');
    await rig.wait(500);
    await rig.tap('Final answer');
    await rig.wait(100);
    expect(rig.game.phase, GamePhase.settle, reason: 'a deliberate tap works');
    await rig.finish();
  });
}
