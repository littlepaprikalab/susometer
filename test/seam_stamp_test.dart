// The main action stamped across the seam between the top card and the
// camera (SPEC.md decision 90): Next and Start the questions on Calibrate,
// Done asking on a party's Ask. Each test pins where the stamp lands, what
// it must not cover, and that it still works as a button.
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
import 'package:susometer/theme/expression_stamp.dart';
import 'package:susometer/screens/intro_screens.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/theme/tokens.dart';

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
    // Past the landing, and past the 600 ms in which Start ignores a double
    // tap on the last Next.
    await wait(700);
  }

  /// Calibration (tapped through by [until]) → the first question's Ask,
  /// once its pulse is in and Done asking has landed.
  Future<void> toAsk() async {
    autoTaps = true;
    if (game.phase == GamePhase.consent) await tap('I agree, measure me');
    // Solo holds its question card up while the phase is already Answer.
    await until(() => game.shownPhase == GamePhase.ask, what: 'calibration');
    await until(() => !game.waitingForPulse, what: 'the pulse');
    await wait(StampButton.landing.inMilliseconds + 100);
  }
}

/// The four corners of [box] on screen, through every transform (the
/// stamp's tilt included).
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

/// The stamp as drawn: the tilted button, shadow included.
List<Offset> stampShape(WidgetTester tester) {
  final drawn = find.descendant(
    of: find.byType(StampButton),
    matching: find.byType(Stack),
  );
  return corners(tester.renderObject<RenderBox>(drawn.first));
}

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
/// the asker card on Ask.
Finder topCardWords() => find.descendant(
  of: find.byType(SeamStampLayout),
  matching: find.byWidgetPredicate(
    (w) => w is RichText,
    description: 'top card words',
  ),
);

bool inside<T extends Widget>(Element e) =>
    e.findAncestorWidgetOfExactType<T>() != null;

/// Checks the stamp labelled [label] where it hangs: across the seam,
/// on screen, clear of the card's words and the camera's chips and stamps,
/// and a labelled tap target.
Future<void> expectOnSeam(
  WidgetTester tester,
  String label,
  Size screen,
) async {
  expect(find.byType(StampButton), findsOneWidget);
  final shape = stampShape(tester);
  final bounds = boundsOf(shape);
  final camera = tester.getRect(find.byType(CameraWindow));
  final layout = tester.widget<SeamStampLayout>(find.byType(SeamStampLayout));
  final cardBottom = camera.top - layout.gap;

  // Across the seam: over the card's bottom edge and the camera's top one.
  expect(bounds.top, lessThan(cardBottom - 4), reason: '$label: $bounds');
  expect(
    bounds.bottom,
    greaterThan(camera.top + 4),
    reason: '$label: $bounds, camera at ${camera.top}',
  );
  // On screen, and in the middle third or so: not stacked on the corner
  // stamp below it.
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(screen.width));
  expect(
    (bounds.center.dx - camera.center.dx).abs(),
    lessThan(2),
    reason: label,
  );

  // None of the card's words under it.
  final clear = [
    for (final e in topCardWords().evaluate())
      if (!inside<StampButton>(e) && !inside<CameraWindow>(e)) e,
  ];
  expect(clear, isNotEmpty, reason: label);
  for (final e in clear) {
    for (final (text, box) in wordBoxes(
      tester,
      find.byElementPredicate((x) => x == e),
    )) {
      expect(
        overlaps(shape, box),
        isFalse,
        reason: '$label covers "$text" at $box (stamp $bounds)',
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
        reason: '$label runs into ${e.widget.runtimeType} at $box',
      );
    }
  }

  // A button VoiceOver reads by its words, a tap target in size.
  final handle = tester.ensureSemantics();
  final node = tester.getSemantics(find.byType(StampButton));
  expect(node.label, label);
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

    testWidgets('Calibrate: Next and Start the questions hang across the '
        'seam, and the camera stays put ($where)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startParty(['Sam', 'Alex']);
      await rig.tap('I agree, measure me');
      rig.autoTaps = false;
      await rig.wait(300);
      // Sitting still: nothing to move on from, so no stamp yet.
      expect(rig.game.currentWarmup, isNull);
      expect(find.byType(StampButton), findsNothing);
      final still = tester.getRect(find.byType(CameraWindow));

      await rig.until(
        () => rig.game.currentWarmup != null,
        what: 'first warm-up',
      );
      await rig.wait(StampButton.landing.inMilliseconds + 100);
      await expectOnSeam(tester, 'Next', screen);
      expect(tester.getRect(find.byType(CameraWindow)), still);
      // Doesn't apply stays at the bottom, under the camera.
      expect(
        tester.getRect(find.text("Doesn't apply")).top,
        greaterThan(still.bottom),
      );

      await rig.toReady();
      await expectOnSeam(tester, 'Start the questions', screen);
      expect(tester.getRect(find.byType(CameraWindow)), still);
      expect(find.text("Doesn't apply"), findsNothing);

      await rig.tap('Start the questions');
      await rig.until(() => rig.game.phase == GamePhase.ask);
      await rig.finish();
    });

    testWidgets('Ask: Done asking hangs across the seam, over the Proof '
        'Panel too, and the camera stays put ($where)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final rig = Rig(tester);
      await rig.pumpApp(size: screen);
      await rig.startParty(['Sam', 'Alex']);
      await rig.toAsk();
      await expectOnSeam(tester, 'Done asking', screen);
      final ask = tester.getRect(find.byType(CameraWindow));
      // Pause keeps its corner, with the hint beside it.
      expect(
        tester.getRect(find.bySemanticsLabel('Pause the game')).top,
        greaterThan(ask.bottom),
      );

      // The Proof Panel sits over the camera and lets touches through; it
      // must not hide the stamp either.
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
      expect(
        overlaps(stampShape(tester), panel),
        isFalse,
        reason:
            'the Proof Panel at $panel covers the stamp at '
            '${boundsOf(stampShape(tester))}',
      );
      await expectOnSeam(tester, 'Done asking', screen);

      // A real tap, through the panel's area, ends the ask.
      await rig.tap('Done asking');
      await rig.wait(300);
      expect(rig.game.phase, GamePhase.answer);
      expect(find.byType(StampButton), findsNothing);
      expect(tester.getRect(find.byType(CameraWindow)), ask);
      await rig.finish();
    });
  }

  testWidgets('every warm-up and calibration line shows whole above its '
      'stamp, on both phones at both text sizes', (tester) async {
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
                        // where the stamp lands depends only on the bubble.
                        child: SeamStampLayout(
                          gap: 12,
                          top: HostBubble(
                            text: text,
                            lines: CalibrateScreen.bubbleLines,
                            minFontSize: CalibrateScreen.bubbleMinFontSize,
                            bottomRoom: StampButton.cardRoom,
                          ),
                          camera: const ColoredBox(color: SusColors.ink),
                          stamp: StampButton(
                            key: ValueKey(label),
                            label: label,
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
          // One frame to start the landing's clock, then all of it.
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump(StampButton.landing);
          final shape = stampShape(tester);
          final words = wordBoxes(
            tester,
            find.descendant(
              of: find.byType(HostBubble),
              matching: find.byType(RichText),
            ),
          );
          expect(words, isNotEmpty);
          for (final (_, box) in words) {
            expect(
              overlaps(shape, box),
              isFalse,
              reason:
                  '$label covers "$text" at $box, ×$scale on $screen '
                  '(stamp ${boundsOf(shape)})',
            );
          }
        }
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  testWidgets('solo has no stamp: its question card is the button', (
    tester,
  ) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam'], mode: GameMode.solo);
    await rig.toAsk();
    expect(rig.game.mode, GameMode.solo);
    expect(find.byType(StampButton), findsNothing);
    expect(find.text('Different question'), findsOneWidget);
    await rig.finish();
  });

  testWidgets('the stamp lands once, then holds still', (tester) async {
    final rig = Rig(tester);
    await rig.pumpApp();
    await rig.startParty(['Sam', 'Alex']);
    await rig.tap('I agree, measure me');
    rig.autoTaps = false;
    await rig.until(() => rig.game.currentWarmup != null, what: 'warm-up');
    await tester.pump();
    final stamp = find.descendant(
      of: find.byType(StampButton),
      matching: find.byType(Stack),
    );
    double size() => boundsOf(corners(tester.renderObject(stamp.first))).width;
    Future<double> landed() async {
      await tester.pump(StampButton.landing);
      await tester.pump();
      return size();
    }

    // Pressed in from above: larger as it appears, its own size once landed.
    await tester.pump(const Duration(milliseconds: 16));
    final dropping = size();
    final settled = await landed();
    expect(dropping, greaterThan(settled * 1.2));
    // Then nothing of it moves: a later frame draws it the same.
    final shape = stampShape(tester);
    await rig.wait(1000);
    expect(stampShape(tester), shape);
    await rig.finish();
  });

  testWidgets('the landing costs one short burst of frames, then one per '
      'tick again', (tester) async {
    // Every frame over the native camera takes the iOS main thread from the
    // camera (decision 78), so the landing must end and nothing of the
    // stamp may keep drawing.
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
    expect(find.byType(StampButton), findsOneWidget);
    final landing = await framesIn(1000);
    final after = await framesIn(1000);
    // A second of 100 ms ticks is 10 frames; the 420 ms landing adds at
    // most its 60 Hz vsyncs.
    final landingVsyncs = StampButton.landing.inMilliseconds * 60 ~/ 1000;
    expect(landing, lessThanOrEqualTo(10 + landingVsyncs + 3));
    expect(landing, greaterThan(after), reason: 'it did animate');
    expect(after, inInclusiveRange(8, 12), reason: '$after frames in 1 s');
    await rig.finish();
  });

  testWidgets('with Reduce Motion the stamp is simply there', (tester) async {
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
    final shape = stampShape(tester);
    await tester.pump(StampButton.landing);
    expect(stampShape(tester), shape);
    await rig.finish();
  });
}
