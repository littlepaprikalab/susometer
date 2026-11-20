// Where the buttons on the seam are, as drawn (SPEC.md decision 90), and
// what they mustn't cover: shared by the seam button tests.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/presage/camera_preview.dart';
import 'package:susometer/theme/expression_stamp.dart';
import 'package:susometer/theme/game_widgets.dart';
import 'package:susometer/theme/seam_button.dart';
import 'package:susometer/theme/widgets.dart';

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

/// Pause, beside the main button on the question screens' seam.
Finder leadingButton() => find.descendant(
  of: find.byType(SeamLayout),
  matching: find.byType(PauseButton),
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
/// it ([leading]: Pause): across the seam, on screen, on
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
