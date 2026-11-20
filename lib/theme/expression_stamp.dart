import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'tokens.dart';

/// Share of the camera's top row, out of 100, that the expression stamp may
/// take. The chips get the rest, so at large text sizes they shrink instead
/// of running under the stamp.
const stampRowFlex = 42;

/// The same for a camera problem's stamp on Ask and Answer. Its words are
/// longer than a #tag, and the chip beside it ("Reading paused") is short.
const issueStampRowFlex = 54;

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

  static const fontSize = _RubberStamp.fontSize;

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
  Widget build(BuildContext context) => _RubberStamp(
    text: '#$label',
    ink: stress ? SusColors.tomatoDeep : SusColors.teal,
    paper: SusColors.cream,
    tiltDegrees: tiltDegrees(label),
    seed: seedFor(label),
    semanticsLabel: 'Expression: $label',
  );
}

/// A camera problem ("Hold still", "Too dark") stamped where the expression
/// tag goes, in mustard ink with ink letters, so it reads as a warning from
/// the show rather than a reading of the player. VoiceOver announces
/// [semanticsLabel] when it appears, as it did the banner it replaced.
class IssueStamp extends StatelessWidget {
  const IssueStamp({super.key, required this.text, this.semanticsLabel});

  /// The stamp's words, short enough to read at a glance.
  final String text;

  /// What VoiceOver reads (the full problem and its fix); [text] if null.
  final String? semanticsLabel;

  static const _tilts = <double>[-5, 4, -7, 3, -4, 6, -6];

  /// Each problem lands at its own angle (degrees), never flat.
  static double tiltDegrees(String text) =>
      _tilts[ExpressionStamp.seedFor(text) % _tilts.length];

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: _RubberStamp(
      text: text,
      ink: SusColors.mustard,
      paper: SusColors.ink,
      tiltDegrees: tiltDegrees(text),
      seed: ExpressionStamp.seedFor(text),
      semanticsLabel: semanticsLabel ?? text,
    ),
  );
}

/// The stamp itself: a block of [ink] with a frame and the words in
/// [paper], worn in a pattern fixed by [seed] and tilted.
class _RubberStamp extends StatelessWidget {
  const _RubberStamp({
    required this.text,
    required this.ink,
    required this.paper,
    required this.tiltDegrees,
    required this.seed,
    required this.semanticsLabel,
  });

  static const fontSize = 18.0;

  final String text;
  final Color ink;
  final Color paper;
  final double tiltDegrees;
  final int seed;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _Tilt(
        angle: tiltDegrees * math.pi / 180,
        child: _Worn(
          seed: seed,
          child: Container(
            padding: const EdgeInsets.all(3.5),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 3, 10, 2),
              decoration: BoxDecoration(
                border: Border.all(color: paper, width: 1.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                semanticsLabel: semanticsLabel,
                style: SusText.display(fontSize, color: paper),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the stamp sits: its top-right corner, with the stamp pressed in
/// when it appears or changes and faded out when it goes. Takes whatever
/// width it's given and shrinks the stamp to fit.
///
/// Shows the expression [tag], or the [issue] in its place while the camera
/// can't get a clean read.
class CameraStampSlot extends StatelessWidget {
  const CameraStampSlot({
    super.key,
    required this.tag,
    required this.stressTags,
    this.issue,
  });

  /// The expression to show, or null for none.
  final String? tag;

  /// Expressions shown in red (they move the score).
  final List<String> stressTags;

  /// A camera problem to stamp instead of the tag, or null for none.
  final IssueStamp? issue;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final issue = this.issue;
    final label = tag;
    // An issue and a tag with the same words are still different stamps.
    final current = ValueKey<String?>(issue != null ? '!${issue.text}' : label);
    final Widget? stamp =
        issue ??
        (label == null
            ? null
            : ExpressionStamp(
                label: label,
                stress: stressTags.contains(label),
              ));
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
          // The old stamp just fades; the new one drops in from above the
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
        child: stamp == null
            ? SizedBox.shrink(key: current)
            : FittedBox(key: current, fit: BoxFit.scaleDown, child: stamp),
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

/// A screen's main action as a rubber stamp hung across the seam between
/// its top card and the camera (SPEC.md decision 90): where the players are
/// already looking, not half a screen below at the bottom.
///
/// It's still a button first: teal like every main action, an ink border
/// and a hard shadow it presses down onto, as on the solo question card
/// (decision 85). The stamp is in the details: a cream frame inside the
/// edge, the words in the display face, a little worn, and a tilt of its
/// own.
///
/// It lands like the camera's stamps when it appears or its words change,
/// then gives one wobble and holds still. Nothing keeps moving: a moving
/// button would redraw the screen on every vsync, over the camera
/// (decision 78).
class StampButton extends StatefulWidget {
  const StampButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tiltDegrees = defaultTiltDegrees,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Negative tips the right end up.
  final double tiltDegrees;

  static const defaultTiltDegrees = -2.5;

  /// The drawn button's height, without its shadow. With the shadow it's a
  /// tap target tall, and the touch area is the whole tilted stamp.
  static const height = 40.0;

  /// Room the card above keeps clear at its bottom, so the stamp's top edge
  /// lands on the card's frame and padding, not on its words.
  static const cardRoom = 10.0;

  static const fontSize = 18.0;

  /// How long it takes to land and settle.
  static const landing = Duration(milliseconds: 420);

  @override
  State<StampButton> createState() => _StampButtonState();
}

class _StampButtonState extends State<StampButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _land = AnimationController(
    vsync: this,
    duration: StampButton.landing,
  );
  bool _down = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _stampIn());
  }

  @override
  void didUpdateWidget(StampButton old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) _stampIn();
  }

  void _stampIn() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _land.value = 1;
    } else {
      _land.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _land.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = _down && enabled;
    const shadow = 4.0;
    final face = Container(
      height: StampButton.height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SusColors.teal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: SusColors.cream, width: 1.6),
          borderRadius: BorderRadius.circular(7),
        ),
        // As wide as its words, and no wider.
        child: Center(
          widthFactor: 1,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: SusColors.cream, size: 20),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  style: SusText.display(
                    StampButton.fontSize,
                    color: SusColors.cream,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final stamp = SizedBox(
      height: StampButton.height + shadow,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: shadow,
            height: StampButton.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: SusColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Sized by the face; the shadow sits behind it.
          AnimatedPadding(
            duration: const Duration(milliseconds: 60),
            padding: EdgeInsets.only(top: pressed ? shadow : 0),
            child: face,
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _land,
            builder: (context, child) {
              final t = _land.value;
              // Drops from above the screen and lands in the first 40%...
              final drop = Curves.easeInCubic.transform((t / 0.4).clamp(0, 1));
              final scale = 1.5 - 0.5 * drop;
              // ...then rocks once either way and settles.
              final settle = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
              final wobble = t <= 0.4
                  ? 0.0
                  : 5 * math.sin(settle * 2 * math.pi) * (1 - settle);
              return Opacity(
                opacity: (t / 0.2).clamp(0.0, 1.0) * (enabled ? 1 : 0.5),
                child: Transform.rotate(
                  angle: wobble * math.pi / 180,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: _Tilt(
              angle: widget.tiltDegrees * math.pi / 180,
              child: _Worn(
                seed: ExpressionStamp.seedFor(widget.label),
                child: stamp,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A top card and the camera under it, with an optional [stamp] hung across
/// the seam between them, in the middle (SPEC.md decision 90): clear of the
/// camera's corner stamp, so the button doesn't read as one more #tag, and
/// under the line the players are reading.
///
/// The camera gets whatever height is left, so the stamp never moves it:
/// with or without a stamp, the two cards are laid out the same. The stamp
/// is laid out last, so it draws over both and takes the touches there.
class SeamStampLayout extends StatelessWidget {
  const SeamStampLayout({
    super.key,
    required this.top,
    required this.camera,
    required this.gap,
    this.stamp,
  });

  final Widget top;
  final Widget camera;
  final double gap;
  final Widget? stamp;

  /// Widest the stamp may be, as a share of the cards' width; a longer label
  /// shrinks to fit.
  static const maxWidthShare = 0.66;

  /// How far the stamp's box reaches into the camera, from its top edge:
  /// past the border, and no further than the chips at 12 pt inside it.
  static const cameraReach = 15.0;

  @override
  Widget build(BuildContext context) {
    final stamp = this.stamp;
    return CustomMultiChildLayout(
      delegate: _SeamDelegate(gap),
      children: [
        LayoutId(id: _Seam.top, child: top),
        LayoutId(
          id: _Seam.camera,
          child: _ReportFloor(child: camera),
        ),
        if (stamp != null) LayoutId(id: _Seam.stamp, child: stamp),
      ],
    );
  }
}

/// How far down the screen a stamp on the seam can reach (from the top of
/// the view), while a [SeamStampLayout] is up; null otherwise. The Proof
/// Panel stays below it, so it never hides the stamp (SPEC.md decision 90).
/// The same with or without a stamp, so the panel doesn't move when one
/// comes or goes.
final seamStampFloor = ValueNotifier<double?>(null);

/// Reports where the camera's top edge is on screen to [seamStampFloor].
class _ReportFloor extends SingleChildRenderObjectWidget {
  const _ReportFloor({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderReportFloor();
}

class _RenderReportFloor extends RenderProxyBox {
  double? _sent;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final floor = localToGlobal(Offset.zero).dy + SeamStampLayout.cameraReach;
    if (floor == _sent) return;
    _sent = floor;
    // Not while painting: the panel rebuilds on the next frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached && _sent == floor) seamStampFloor.value = floor;
    });
  }

  @override
  void detach() {
    final sent = _sent;
    _sent = null;
    super.detach();
    if (sent == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (seamStampFloor.value == sent) seamStampFloor.value = null;
    });
  }
}

enum _Seam { top, camera, stamp }

class _SeamDelegate extends MultiChildLayoutDelegate {
  _SeamDelegate(this.gap);

  final double gap;

  @override
  void performLayout(Size size) {
    final top = layoutChild(
      _Seam.top,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    positionChild(_Seam.top, Offset.zero);
    final cameraTop = top.height + gap;
    layoutChild(
      _Seam.camera,
      BoxConstraints.tight(
        Size(size.width, math.max(0, size.height - cameraTop)),
      ),
    );
    positionChild(_Seam.camera, Offset(0, cameraTop));
    if (hasChild(_Seam.stamp)) {
      final stamp = layoutChild(
        _Seam.stamp,
        BoxConstraints(maxWidth: size.width * SeamStampLayout.maxWidthShare),
      );
      positionChild(
        _Seam.stamp,
        Offset(
          (size.width - stamp.width) / 2,
          cameraTop + SeamStampLayout.cameraReach - stamp.height,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_SeamDelegate old) => old.gap != gap;
}
