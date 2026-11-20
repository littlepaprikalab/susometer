// The buttons hung across the seam between the top card and the camera
// (SPEC.md decision 90): Next, then Start the questions on Calibrate; Pause
// with Done asking, Final answer or what's being waited for on the
// question screens. Each test
// pins where they hang, what they must not cover, and that they still work
// as buttons.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/debug/proof_panel.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/screens/intro_screens.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/theme/seam_button.dart';
import 'package:susometer/theme/tokens.dart';
import 'package:susometer/theme/widgets.dart';
import 'package:susometer/voice/speech_service.dart';

import 'rig.dart';
import 'seam_geometry.dart';

extension on Rig {
  Future<void> startParty(List<String> names, {GameMode? mode}) async {
    presage.storedKey = 'k';
    for (final n in names) {
      await addPlayer(n);
    }
    if (mode == GameMode.solo) await tap('Solo · host asks');
    await tap('3');
    await tap('Start the show');
    await wait(300);
    if (game.phase == GamePhase.howToPlay) await tap("Got it, let's play");
  }

  /// Through the warm-ups to Start the questions, tapping Next as a player
  /// would once each warm-up is answered.
  Future<void> toReady() async {
    autoTaps = false;
    await until(() {
      final w = game.currentWarmup;
      if (w != null && w.latencyS != null && !presage.talking) {
        game.nextWarmup();
      }
      return game.calibStage == CalibStage.ready;
    }, what: 'the normal to lock in');
    // Past the pop-in, and past the 600 ms in which Start ignores a double
    // tap on the last Next.
    await wait(700);
  }

  /// Calibration (tapped through by [until]) → the first question's Ask,
  /// once its pulse is in and Done asking has popped in.
  Future<void> toAsk() async {
    autoTaps = true;
    if (game.phase == GamePhase.consent) await tap('I agree, measure me');
    // Solo holds its question card up while the phase is already Answer.
    await until(() => game.shownPhase == GamePhase.ask, what: 'calibration');
    await until(() => !game.waitingForPulse, what: 'the pulse');
    await wait(SeamButton.entrance.inMilliseconds + 100);
  }
}

void main() {
  const sizes = [
    (Size(390, 844), 1.0),
    (Size(390, 844), 1.3),
    (Size(375, 667), 1.0),
    (Size(375, 667), 1.3),
  ];

  for (final (screen, scale) in sizes) {
    final where =
        '${screen.width.round()}×${screen.height.round()}, '
        'text ×$scale';

    testWidgets('Calibrate: Next, then Start the questions, hang across the '
        'seam; the camera stays put ($where)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startParty(['Sam', 'Alex']);
      await rig.tap('I agree, measure me');
      rig.autoTaps = false;
      await rig.wait(300);
      // Sitting still: nothing to move on from, so no buttons yet.
      expect(rig.game.currentWarmup, isNull);
      expect(find.byType(SeamButton), findsNothing);
      final still = tester.getRect(find.byType(CameraWindow));

      await rig.until(
        () => rig.game.currentWarmup != null,
        what: 'first warm-up',
      );
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      await expectOnSeam(tester, 'Next', screen, leading: null);
      // No skipping a warm-up: they fit anyone (SPEC.md decision 90).
      expect(find.text("Doesn't apply"), findsNothing);
      expect(find.text('Tap here when done speaking'), findsOneWidget);
      expect(tester.getRect(find.byType(CameraWindow)), still);
      // Nothing left under the camera: no button, no hint.
      for (final e in find.byType(ChunkyButton).evaluate()) {
        final box = e.renderObject! as RenderBox;
        expect(
          box.localToGlobal(Offset.zero).dy,
          lessThan(still.bottom),
          reason: '${(e.widget as ChunkyButton).label} under the camera',
        );
      }
      expect(find.text('Answer out loud, then tap Next.'), findsNothing);
      // Nor a status line between the progress and the host's bubble.
      expect(find.textContaining('from the easy deck'), findsNothing);

      await rig.toReady();
      await expectOnSeam(tester, 'Start the questions', screen, leading: null);
      expect(find.text('Tap when ready · Alex asks first'), findsOneWidget);
      expect(tester.getRect(find.byType(CameraWindow)), still);

      await rig.tap('Start the questions');
      await rig.until(() => rig.game.phase == GamePhase.ask);
      await rig.finish();
    });

    testWidgets('Ask: Done asking and Pause hang across the seam, over the '
        'Proof Panel too; Pause stays put through the question ($where)', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startParty(['Sam', 'Alex']);
      await rig.toAsk();
      await expectOnSeam(tester, 'Done asking', screen, leading: 'Pause');
      expect(find.text('Sam: tap here, then answer'), findsOneWidget);
      final ask = tester.getRect(find.byType(CameraWindow));
      final pause = tester.getRect(leadingButton());

      // A long question fills the card: its newest words stay clear too.
      rig.say(
        'Have you ever told a friend you loved a present they gave you, '
        'then quietly given it to someone else at the next birthday party '
        'you went to, hoping nobody would ever notice',
      );
      await rig.wait(300);
      await expectOnSeam(tester, 'Done asking', screen, leading: 'Pause');

      // The Proof Panel sits over the camera and lets touches through; it
      // must not hide the buttons either.
      rig.services.settings.proofPanel = true;
      await rig.wait(300);
      expect(find.byType(ProofPanel), findsOneWidget);
      final panel = tester.getRect(
        find
            .descendant(
              of: find.byType(ProofPanel),
              matching: find.byType(Container),
            )
            .first,
      );
      for (final shape in [buttonShape(tester), leadingShape(tester)]) {
        expect(
          overlaps(shape, panel),
          isFalse,
          reason: 'the Proof Panel at $panel covers ${boundsOf(shape)}',
        );
      }
      await expectOnSeam(tester, 'Done asking', screen, leading: 'Pause');

      // A real tap, through the panel's area, ends the ask. Pause and the
      // camera stay where they were, answering and locking in.
      await rig.tap('Done asking');
      await rig.wait(300);
      expect(rig.game.phase, GamePhase.answer);
      expect(tester.getRect(find.byType(CameraWindow)), ask);
      expect(tester.getRect(leadingButton()), pause);
      // Final answer takes Done asking's place, popping in with its words.
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      await expectOnSeam(tester, 'Final answer', screen, leading: 'Pause');
      expect(find.text("Tap here when you're done"), findsOneWidget);
      rig.services.settings.proofPanel = false;
      rig.presage.talk(true);
      await rig.wait(1500);
      rig.presage.talk(false);
      await rig.wait(300);
      // The answer card's words, and its "Took … to start answering", clear
      // of Pause.
      final paused = leadingShape(tester);
      for (final e in topCardWords().evaluate()) {
        if (inside<CameraWindow>(e) || inside<PauseButton>(e)) continue;
        for (final (text, box) in wordBoxes(
          tester,
          find.byElementPredicate((x) => x == e),
        )) {
          expect(overlaps(paused, box), isFalse, reason: 'Pause covers $text');
        }
      }
      await rig.tap('Final answer');
      await rig.wait(300);
      expect(rig.game.phase, GamePhase.settle);
      expect(tester.getRect(leadingButton()), pause);
      expect(tester.getRect(find.byType(CameraWindow)), ask);
      // Locking in: no button, its status where the button was.
      expect(find.byType(SeamButton), findsNothing);
      final status = tester.getRect(find.text('Locking in the reading…'));
      expect(
        status.right,
        lessThanOrEqualTo(ask.right - SeamLayout.rightInset),
      );
      expect(status.top, lessThan(ask.top));
      expect(status.bottom, greaterThan(ask.top - layoutGap(tester) - 30));
      // Nothing under the camera, in any phase.
      expect(
        tester.getRect(find.bySemanticsLabel('Pause the game')).bottom,
        lessThan(ask.top + SeamLayout.cameraReach + 1),
      );
      await rig.finish();
    });
  }

  testWidgets('every warm-up and calibration line shows whole above its '
      'buttons, on both phones at both text sizes', (tester) async {
    final warmups = [
      for (final q
          in (jsonDecode(File('assets/decks/warmup.json').readAsStringSync())
                  as Map)['questions']
              as List)
        (q as Map)['q'] as String,
      for (final w in DeckLibrary.fallback.warmup) w.text,
    ];
    final lines = [
      for (final w in warmups) (w, 'Next'),
      ("That's your normal locked in.", 'Start the questions'),
      ("That's your normal locked in.", 'Back to the questions'),
    ];
    for (final screen in const [Size(390, 844), Size(375, 667)]) {
      for (final scale in [1.0, 1.3]) {
        useRealPhone(tester, screen);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final (text, label) in lines) {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildSusTheme(),
              home: Scaffold(
                body: ScreenFrame(
                  child: Column(
                    children: [
                      Expanded(
                        // As on Calibrate, with a plain box for the camera:
                        // where the buttons hang depends only on the bubble.
                        child: SeamLayout(
                          gap: 12,
                          top: HostBubble(
                            text: text,
                            lines: CalibrateScreen.bubbleLines,
                            minFontSize: CalibrateScreen.bubbleMinFontSize,
                            bottomRoom: SeamButton.cardRoom,
                          ),
                          camera: const ColoredBox(color: SusColors.ink),
                          button: SeamButton(
                            key: ValueKey(label),
                            label: label,
                            hint: label == 'Next'
                                ? 'Tap here when done speaking'
                                : 'Tap when ready · Christopher-Alexand asks '
                                      'first',
                            icon: label == 'Next'
                                ? Icons.skip_next_rounded
                                : null,
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          // One frame to start the pop-in's clock, then all of it.
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump(SeamButton.entrance);
          final shapes = [buttonShape(tester)];
          final words = wordBoxes(
            tester,
            find.descendant(
              of: find.byType(HostBubble),
              matching: find.byType(RichText),
            ),
          );
          expect(words, isNotEmpty);
          for (final shape in shapes) {
            for (final (_, box) in words) {
              expect(
                overlaps(shape, box),
                isFalse,
                reason:
                    'a button covers "$text" at $box, ×$scale on $screen '
                    '(button ${boundsOf(shape)})',
              );
            }
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('solo: Pause on the seam, Different question on the card, '
      'Final answer on the seam once the card is tapped', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam'], mode: GameMode.solo);
    await rig.toAsk();
    expect(rig.game.mode, GameMode.solo);
    expect(rig.game.soloHoldsQuestion, isTrue);
    // The card is the way on (decision 85): no button at the seam's right.
    expect(find.byType(SeamButton), findsNothing);
    final camera = tester.getRect(find.byType(CameraWindow));
    final pause = tester.getRect(leadingButton());
    expect(pause.top, lessThan(camera.top));
    expect(pause.bottom, greaterThan(camera.top));
    // Different question on the card's top row, well above its drawn
    // button, and nothing under the camera.
    final different = tester.getRect(
      find.bySemanticsLabel('Different question'),
    );
    expect(different.bottom, lessThan(camera.top - 100));
    final q = rig.game.questionText;
    await rig.tap('Different question');
    await rig.wait(300);
    expect(rig.game.questionText, isNot(q));
    expect(rig.game.soloHoldsQuestion, isTrue);
    expect(find.text('Tap the question, then answer out loud.'), findsNothing);

    await waitOutTapGuard(tester);
    await tester.tapAt(tester.getCenter(find.text(rig.game.questionText)));
    await tester.pump(const Duration(milliseconds: 60));
    await rig.wait(SeamButton.entrance.inMilliseconds + 100);
    expect(rig.game.soloHoldsQuestion, isFalse);
    await expectOnSeam(
      tester,
      'Final answer',
      const Size(390, 844),
      leading: 'Pause',
    );
    expect(tester.getRect(leadingButton()), pause);
    expect(tester.getRect(find.byType(CameraWindow)), camera);
    await rig.finish();
  });

  testWidgets('the button pops in once, then holds still', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.tap('I agree, measure me');
    rig.autoTaps = false;
    await rig.until(() => rig.game.currentWarmup != null, what: 'warm-up');
    await tester.pump();
    double size() => boundsOf(buttonShape(tester)).width;
    // Smaller as it appears, its own size once in.
    await tester.pump(const Duration(milliseconds: 16));
    final popping = size();
    await tester.pump(SeamButton.entrance);
    await tester.pump();
    final settled = size();
    expect(popping, lessThan(settled * 0.9));
    // Level once settled, and nothing of it moves after.
    final shape = buttonShape(tester);
    expect(shape[0].dy, moreOrLessEquals(shape[1].dy, epsilon: 0.01));
    await rig.wait(1000);
    expect(buttonShape(tester), shape);
    await rig.finish();
  });

  testWidgets('the pop-in costs one short burst of frames, then one per '
      'tick again', (tester) async {
    // Every frame over the native camera takes the iOS main thread from the
    // camera (decision 78), so the pop-in must end and nothing of the
    // button may keep drawing.
    Future<int> framesIn(int ms) async {
      var frames = 0;
      for (var i = 0; i < ms * 60 ~/ 1000; i++) {
        await tester.binding.delayed(const Duration(microseconds: 16667));
        if (tester.binding.hasScheduledFrame) {
          frames++;
          await tester.pump();
        }
      }
      return frames;
    }

    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.tap('I agree, measure me');
    rig.autoTaps = false;
    while (rig.game.currentWarmup == null) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(SeamButton), findsOneWidget);
    final popping = await framesIn(1000);
    final after = await framesIn(1000);
    // A second of 100 ms ticks is 10 frames; the 420 ms pop-in adds at most
    // its 60 Hz vsyncs.
    final vsyncs = SeamButton.entrance.inMilliseconds * 60 ~/ 1000;
    expect(popping, lessThanOrEqualTo(10 + vsyncs + 3));
    expect(popping, greaterThan(after), reason: 'it did animate');
    expect(after, inInclusiveRange(8, 12), reason: '$after frames in 1 s');
    await rig.finish();
  });

  testWidgets('with Reduce Motion the button is simply there', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await rig.startParty(['Sam', 'Alex']);
    await rig.tap('I agree, measure me');
    rig.autoTaps = false;
    await rig.until(() => rig.game.currentWarmup != null, what: 'warm-up');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final shape = buttonShape(tester);
    await tester.pump(SeamButton.entrance);
    expect(buttonShape(tester), shape);
    await rig.finish();
  });

  testWidgets('elsewhere the hint is on its button too: Permissions, and No '
      'clean read with its buttons under the card', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    rig.speech.permissions = const SpeechPermissions(
      mic: 'denied',
      speech: 'authorized',
      onDevice: true,
    );
    await rig.startParty(['Sam', 'Alex']);
    expect(rig.game.phase, GamePhase.permissions);
    // The no-mic note is on Play without voice, not over the buttons.
    expect(
      find.text('No transcripts · you tap between question and answer'),
      findsOneWidget,
    );
    expect(find.textContaining('No mic?'), findsNothing);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('Play without voice')).hint,
      'No transcripts · you tap between question and answer',
    );
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
    await rig.tap('Play without voice');
    await rig.wait(300);
    if (rig.game.phase == GamePhase.howToPlay) {
      await rig.tap("Got it, let's play");
    }

    // A question too dark to read: No clean read.
    await rig.toAsk();
    rig.game.doneAsking();
    rig.presage.code = 'TOO_DARK';
    await rig.wait(2500);
    await rig.tap('Final answer');
    await rig.until(() => rig.game.phase == GamePhase.redo, what: 'redo');
    await rig.wait(300);
    final card = tester.getRect(
      find.ancestor(
        of: find.text('Shaky readings never get a score. No fake verdicts.'),
        matching: find.byType(SusCard),
      ),
    );
    final again = tester.getRect(
      find.widgetWithText(ChunkyButton, 'Ask it again'),
    );
    final skip = tester.getRect(find.widgetWithText(ChunkyButton, 'Skip it'));
    // Right under the card that says why, not at the foot of the screen.
    expect(again.top - card.bottom, inInclusiveRange(0, 24));
    expect(skip.top, again.top);
    expect(find.text('Same question, fresh reading'), findsOneWidget);
    expect(tester.takeException(), isNull);
    rig.presage.code = 'OK';
    await rig.finish();
  });
}
