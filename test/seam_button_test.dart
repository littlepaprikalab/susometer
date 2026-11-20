// The buttons hung across the seam between the top card and the camera
// (SPEC.md decision 90): Next or Start the questions with Doesn't apply on
// Calibrate, Done asking with Pause on a party's question screens. Each test
// pins where they hang, what they must not cover, and that they still work
// as buttons.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/debug/proof_panel.dart';
import 'package:susometer/game/decks.dart';
import 'package:susometer/game/game_controller.dart';
import 'package:susometer/game/models.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/screens/intro_screens.dart';
import 'package:susometer/theme/expression_stamp.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/theme/seam_button.dart';
import 'package:susometer/theme/tokens.dart';
import 'package:susometer/theme/widgets.dart';

import 'rig.dart';

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

/// The four corners of [box] on screen, through every transform (the
/// pop-in's scale and wobble included).
List<Offset> corners(RenderBox box) {
  final m = box.getTransformTo(null);
  final s = box.size;
  return [
    for (final p in [
      Offset.zero,
      Offset(s.width, 0),
      Offset(s.width, s.height),
      Offset(0, s.height),
    ])
      MatrixUtils.transformPoint(m, p),
  ];
}

Rect boundsOf(List<Offset> points) => Rect.fromLTRB(
  points.map((p) => p.dx).reduce(math.min),
  points.map((p) => p.dy).reduce(math.min),
  points.map((p) => p.dx).reduce(math.max),
  points.map((p) => p.dy).reduce(math.max),
);

/// Whether the convex [poly] and [rect] overlap by more than [slop]
/// (separating axes: the rectangle's two and the polygon's edges).
bool overlaps(List<Offset> poly, Rect rect, {double slop = 0.5}) {
  final r = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
  final axes = <Offset>[
    const Offset(1, 0),
    const Offset(0, 1),
    for (var i = 0; i < poly.length; i++)
      () {
        final e = poly[(i + 1) % poly.length] - poly[i];
        return Offset(-e.dy, e.dx) / e.distance;
      }(),
  ];
  for (final a in axes) {
    double dot(Offset p) => p.dx * a.dx + p.dy * a.dy;
    final p = poly.map(dot);
    final q = r.map(dot);
    final gap = math.max(
      q.reduce(math.min) - p.reduce(math.max),
      p.reduce(math.min) - q.reduce(math.max),
    );
    if (gap > -slop) return false;
  }
  return true;
}

/// The main button as drawn, shadow included.
List<Offset> buttonShape(WidgetTester tester) {
  final drawn = find.descendant(
    of: find.byType(SeamButton),
    matching: find.byType(Stack),
  );
  return corners(tester.renderObject<RenderBox>(drawn.first));
}

/// Pause or Doesn't apply, whichever is beside it on the seam.
Finder leadingButton() => find.descendant(
  of: find.byType(SeamLayout),
  matching: find.byWidgetPredicate(
    (w) =>
        w is PauseButton || (w is ChunkyButton && w.label == "Doesn't apply"),
    description: 'Pause or Doesn\'t apply',
  ),
);

List<Offset> leadingShape(WidgetTester tester) =>
    corners(tester.renderObject<RenderBox>(leadingButton()));

/// Every line of words in [paragraphs], as boxes on screen: each line from
/// its top to its bottom as laid out, as wide as its words. (Selection boxes
/// would use the display face's ascent and descent, which reach about 5 pt
/// past its tight line height on each side.)
List<(String, Rect)> wordBoxes(WidgetTester tester, Finder paragraphs) {
  final boxes = <(String, Rect)>[];
  for (final e in paragraphs.evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final text = p.text.toPlainText();
    if (text.trim().isEmpty) continue;
    final m = p.getTransformTo(null);
    final painter = TextPainter(
      text: p.text,
      textAlign: p.textAlign,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
      maxLines: p.maxLines,
      strutStyle: p.strutStyle,
      textWidthBasis: p.textWidthBasis,
      textHeightBehavior: p.textHeightBehavior,
    )..layout(maxWidth: p.size.width);
    final lines = painter.computeLineMetrics();
    painter.dispose();
    for (final line in lines) {
      final box = Rect.fromLTWH(
        line.left,
        line.baseline - line.ascent,
        line.width,
        line.ascent + line.descent,
      );
      boxes.add((text, MatrixUtils.transformRect(m, box)));
    }
  }
  return boxes;
}

/// The words in the card above the camera: the host's bubble on Calibrate,
/// the asker's or the answer card on the question screens.
Finder topCardWords() => find.descendant(
  of: find.byType(SeamLayout),
  matching: find.byWidgetPredicate(
    (w) => w is RichText,
    description: 'top card words',
  ),
);

double layoutGap(WidgetTester tester) =>
    tester.widget<SeamLayout>(find.byType(SeamLayout)).gap;

bool inside<T extends Widget>(Element e) =>
    e.findAncestorWidgetOfExactType<T>() != null;

/// Checks the button labelled [label] where it hangs, and the one beside
/// it ([leading]: Pause or Doesn't apply): across the seam, on screen, on
/// one row, clear of each other, of the card's words and of the camera's
/// chips and stamps, and labelled tap targets.
Future<void> expectOnSeam(
  WidgetTester tester,
  String label,
  Size screen, {
  required String? leading,
}) async {
  expect(find.byType(SeamButton), findsOneWidget);
  final camera = tester.getRect(find.byType(CameraWindow));
  final layout = tester.widget<SeamLayout>(find.byType(SeamLayout));
  final cardBottom = camera.top - layout.gap;
  final shapes = <String, List<Offset>>{label: buttonShape(tester)};
  if (leading != null) {
    expect(leadingButton(), findsOneWidget, reason: leading);
    shapes[leading] = leadingShape(tester);
  } else {
    expect(leadingButton(), findsNothing);
  }

  for (final MapEntry(key: name, value: shape) in shapes.entries) {
    final bounds = boundsOf(shape);
    // Across the seam: over the card's bottom edge and the camera's top one.
    expect(bounds.top, lessThan(cardBottom - 4), reason: '$name: $bounds');
    expect(
      bounds.bottom,
      greaterThan(camera.top + 4),
      reason: '$name: $bounds, camera at ${camera.top}',
    );
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(screen.width));

    // None of the card's words under it.
    final clear = [
      for (final e in topCardWords().evaluate())
        if (!inside<SeamButton>(e) &&
            !inside<CameraWindow>(e) &&
            !inside<ChunkyButton>(e) &&
            !inside<PauseButton>(e))
          e,
    ];
    expect(clear, isNotEmpty, reason: name);
    for (final e in clear) {
      for (final (text, box) in wordBoxes(
        tester,
        find.byElementPredicate((x) => x == e),
      )) {
        expect(
          overlaps(shape, box),
          isFalse,
          reason: '$name covers "$text" at $box (button $bounds)',
        );
      }
    }

    // Clear of the camera's chips and its #tag or problem stamp.
    for (final f in [
      find.descendant(
        of: find.byType(CameraWindow),
        matching: find.byType(DotChip),
      ),
      find.byType(ExpressionStamp),
      find.byType(IssueStamp),
    ]) {
      for (final e in f.evaluate()) {
        final box = boundsOf(corners(e.renderObject! as RenderBox));
        expect(
          overlaps(shape, box),
          isFalse,
          reason: '$name runs into ${e.widget.runtimeType} at $box',
        );
      }
    }
  }

  // The main button at the right; the other at the left, on its row and
  // clear of it.
  final main = boundsOf(shapes[label]!);
  expect(
    main.right,
    moreOrLessEquals(camera.right - SeamLayout.rightInset, epsilon: 1),
    reason: label,
  );
  if (leading != null) {
    final other = boundsOf(shapes[leading]!);
    expect(
      other.left,
      moreOrLessEquals(camera.left + SeamLayout.leftInset, epsilon: 1),
      reason: leading,
    );
    expect(other.center.dy, moreOrLessEquals(main.center.dy, epsilon: 1));
    expect(main.left - other.right, greaterThanOrEqualTo(8));
  }

  // Buttons VoiceOver reads by their words, tap targets in size.
  final handle = tester.ensureSemantics();
  final node = tester.getSemantics(find.byType(SeamButton));
  expect(node.label, label);
  expect(node.hint, isNotEmpty);
  expect(node.flagsCollection.isButton, isTrue);
  expect(node.rect.width, greaterThanOrEqualTo(44));
  expect(node.rect.height, greaterThanOrEqualTo(44));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
  expect(tester.takeException(), isNull);
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

    testWidgets('Calibrate: Next with Doesn\'t apply, then Start the '
        'questions, hang across the seam; the camera stays put ($where)', (
      tester,
    ) async {
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
      expect(find.text("Doesn't apply"), findsNothing);
      final still = tester.getRect(find.byType(CameraWindow));

      await rig.until(
        () => rig.game.currentWarmup != null,
        what: 'first warm-up',
      );
      await rig.wait(SeamButton.entrance.inMilliseconds + 100);
      await expectOnSeam(tester, 'Next', screen, leading: "Doesn't apply");
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
                          leading: label == 'Next'
                              ? SizedBox(
                                  width: 128,
                                  child: ChunkyButton.light(
                                    label: "Doesn't apply",
                                    height: 46,
                                    fontSize: 15,
                                    onPressed: () {},
                                  ),
                                )
                              : null,
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
          final shapes = [
            buttonShape(tester),
            if (label == 'Next') leadingShape(tester),
          ];
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
}
