import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'tokens.dart';

/// Share of the camera's top row, out of 100, that the expression stamp may
/// take. The chips get the rest, so a long name shrinks instead of running
/// under the stamp.
const stampRowFlex = 42;

/// The player's strongest expression as a rubber-stamped #tag on the camera
/// (mock: docs/design/mocks/ExpressionStamp.png): a solid block of ink with
/// a cream frame and the tag knocked out in cream, worn in spots so the
/// camera shows through, and a slight tilt of its own.
///
/// Red ink for the expressions that move the Sus score, teal for the rest.
class ExpressionStamp extends StatelessWidget {
  const ExpressionStamp({super.key, required this.label, required this.stress});

  /// SDK category, lowercase (e.g. "surprise").
  final String label;

  /// True for an expression the score counts (ScoringConfig.exprCategories).
  final bool stress;

  static const fontSize = 18.0;

  /// Each tag lands at its own angle, like a fresh stamp (degrees).
  static double tiltDegrees(String label) => switch (label) {
    'surprise' => -7,
    'fear' => -5,
    'contempt' => 5,
    'disgust' => -8,
    'happy' => 4,
    'neutral' => -4,
    'sad' => 3,
    'angry' => -6,
    _ => -6,
  };

  /// Seeds the worn-ink pattern, so a tag looks the same every time.
  static int seedFor(String label) =>
      label.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x7fffffff);

  @override
  Widget build(BuildContext context) {
    final ink = stress ? SusColors.tomatoDeep : SusColors.teal;
    return RepaintBoundary(
      child: _Tilt(
        angle: tiltDegrees(label) * math.pi / 180,
        child: _Worn(
          seed: seedFor(label),
          child: Container(
            padding: const EdgeInsets.all(3.5),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 3, 10, 2),
              decoration: BoxDecoration(
                border: Border.all(color: SusColors.cream, width: 1.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#$label',
                maxLines: 1,
                softWrap: false,
                semanticsLabel: 'Expression: $label',
                style: SusText.display(fontSize, color: SusColors.cream),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the stamp sits: its top-right corner, with the tag stamped in when
/// it appears or changes and faded out when it goes. Takes whatever width
/// it's given and shrinks the stamp to fit.
class ExpressionStampSlot extends StatelessWidget {
  const ExpressionStampSlot({
    super.key,
    required this.tag,
    required this.stressTags,
  });

  /// The expression to show, or null for none.
  final String? tag;

  /// Expressions shown in red (they move the score).
  final List<String> stressTags;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final current = ValueKey<String?>(tag);
    final label = tag;
    return Align(
      alignment: Alignment.topRight,
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : const Duration(milliseconds: 200),
        reverseDuration: still
            ? Duration.zero
            : const Duration(milliseconds: 150),
        layoutBuilder: (top, previous) => Stack(
          alignment: Alignment.topRight,
          clipBehavior: Clip.none,
          children: [...previous, ?top],
        ),
        transitionBuilder: (child, animation) {
          // The old tag just fades; the new one drops in from above the
          // canvas and lands.
          if (child.key != current) {
            return FadeTransition(opacity: animation, child: child);
          }
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.5),
            ),
            child: ScaleTransition(
              scale: Tween(begin: 1.55, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeInCubic),
              ),
              child: child,
            ),
          );
        },
        child: label == null
            ? SizedBox.shrink(key: current)
            : FittedBox(
                key: current,
                fit: BoxFit.scaleDown,
                child: ExpressionStamp(
                  label: label,
                  stress: stressTags.contains(label),
                ),
              ),
      ),
    );
  }
}

/// Rotates its child about the centre and takes the size of the rotated
/// box, so whatever lays it out knows how much room the tilt needs.
class _Tilt extends SingleChildRenderObjectWidget {
  const _Tilt({required this.angle, super.child});

  final double angle;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTilt(angle);

  @override
  void updateRenderObject(BuildContext context, _RenderTilt renderObject) {
    renderObject.angle = angle;
  }
}

class _RenderTilt extends RenderProxyBox {
  _RenderTilt(this._angle);

  double _angle;
  set angle(double value) {
    if (value == _angle) return;
    _angle = value;
    markNeedsLayout();
  }

  Size _rotated(Size s) {
    final c = math.cos(_angle).abs();
    final n = math.sin(_angle).abs();
    return Size(s.width * c + s.height * n, s.width * n + s.height * c);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(
      _rotated(child.getDryLayout(constraints.loosen())),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(_rotated(child.size));
  }

  Matrix4 get _transform {
    final c = child!.size;
    return Matrix4.translationValues(size.width / 2, size.height / 2, 0)
      ..multiply(Matrix4.rotationZ(_angle))
      ..multiply(Matrix4.translationValues(-c.width / 2, -c.height / 2, 0));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child, offset),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}

/// Knocks small worn spots out of its child, like a rubber stamp short on
/// ink: specks, nicks along the edges and a few dry streaks, in a pattern
/// fixed by [seed].
class _Worn extends SingleChildRenderObjectWidget {
  const _Worn({required this.seed, super.child});

  final int seed;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWorn(seed);

  @override
  void updateRenderObject(BuildContext context, _RenderWorn renderObject) {
    renderObject.seed = seed;
  }
}

class _RenderWorn extends RenderProxyBox {
  _RenderWorn(this._seed);

  int _seed;
  set seed(int value) {
    if (value == _seed) return;
    _seed = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    // The spots are cut from a layer holding only the stamp, which needs
    // the child to paint on this canvas (plain boxes and text do).
    if (child.needsCompositing || size.isEmpty) {
      context.paintChild(child, offset);
      return;
    }
    final canvas = context.canvas;
    final w = size.width;
    final h = size.height;
    canvas.saveLayer(offset & size, Paint());
    context.paintChild(child, offset);
    final r = math.Random(_seed);
    final cut = Paint()..blendMode = BlendMode.dstOut;
    final specks = (w * h / 70).round();
    for (var i = 0; i < specks; i++) {
      canvas.drawCircle(
        offset + Offset(r.nextDouble() * w, r.nextDouble() * h),
        0.35 + r.nextDouble() * 0.9,
        cut,
      );
    }
    for (var i = 0; i < 14; i++) {
      final along = r.nextDouble();
      final edge = switch (r.nextInt(4)) {
        0 => Offset(along * w, 0),
        1 => Offset(w, along * h),
        2 => Offset(along * w, h),
        _ => Offset(0, along * h),
      };
      canvas.drawCircle(offset + edge, 0.8 + r.nextDouble() * 1.6, cut);
    }
    final dry = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = const Color(0x8C000000);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          offset.dx + r.nextDouble() * w * 0.6,
          offset.dy + r.nextDouble() * h,
          w * (0.2 + r.nextDouble() * 0.3),
          0.7,
        ),
        dry,
      );
    }
    canvas.restore();
  }
}
