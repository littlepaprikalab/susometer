import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'tokens.dart';

/// A screen's main action, hung across the seam between its top card and
/// the camera, at the right (SPEC.md decision 90): where the players are
/// already looking, not half a screen below at the bottom.
///
/// It's the app's main button, plain: teal, an ink border and a hard shadow
/// it presses down onto, the label in the body face. Under the label, in
/// small type, says when to tap it ([hint]), so the button carries its own
/// instruction instead of a line at the bottom of the screen.
///
/// It pops in with one wobble when it appears or its label changes, then
/// holds still. Nothing keeps moving: a moving button would redraw the
/// screen on every vsync, over the camera (decision 78).
class SeamButton extends StatefulWidget {
  const SeamButton({
    super.key,
    required this.label,
    required this.hint,
    required this.onPressed,
    this.icon,
  });

  final String label;

  /// When to tap it ("Tap here when done speaking").
  final String hint;

  final VoidCallback? onPressed;
  final IconData? icon;

  /// The drawn button's height, without its shadow.
  static const height = 54.0;

  static const fontSize = 17.0;
  static const hintSize = 12.5;

  /// How long it takes to pop in and settle.
  static const entrance = Duration(milliseconds: 420);

  /// Room the card above keeps clear at its bottom, so the button's top
  /// edge lands on the card's frame and padding, not on its words.
  static const cardRoom = 20.0;

  @override
  State<SeamButton> createState() => _SeamButtonState();
}

class _SeamButtonState extends State<SeamButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: SeamButton.entrance,
  );
  bool _down = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _popIn());
  }

  @override
  void didUpdateWidget(SeamButton old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) _popIn();
  }

  void _popIn() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _in.value = 1;
    } else {
      _in.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = _down && enabled;
    final shadow = SusShape.shadowOffset.dy;
    final face = Container(
      height: SeamButton.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: SusColors.teal,
        borderRadius: BorderRadius.circular(SusShape.buttonRadius),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      // As wide as its words, and no wider.
      child: Center(
        widthFactor: 1,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      color: SusColors.cream,
                      size: SeamButton.fontSize + 5,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    style: SusText.body(
                      SeamButton.fontSize,
                      weight: FontWeight.w700,
                      color: SusColors.cream,
                    ),
                  ),
                ],
              ),
              Text(
                widget.hint,
                maxLines: 1,
                softWrap: false,
                style: SusText.body(
                  SeamButton.hintSize,
                  weight: FontWeight.w600,
                  color: SusColors.cream,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final button = SizedBox(
      height: SeamButton.height + shadow,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: shadow,
            height: SeamButton.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: SusColors.ink,
                borderRadius: BorderRadius.circular(SusShape.buttonRadius),
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
      hint: widget.hint,
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
            animation: _in,
            builder: (context, child) {
              final t = _in.value;
              // Pops up from a little smaller in the first 40%...
              final pop = Curves.easeOutBack.transform(
                (t / 0.4).clamp(0.0, 1.0),
              );
              final scale = 0.75 + 0.25 * pop;
              // ...then rocks once either way and settles level.
              final settle = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
              final wobble = t <= 0.4
                  ? 0.0
                  : 4 * math.sin(settle * 2 * math.pi) * (1 - settle);
              return Opacity(
                opacity: (t / 0.2).clamp(0.0, 1.0) * (enabled ? 1 : 0.5),
                child: Transform.rotate(
                  angle: wobble * math.pi / 180,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: button,
          ),
        ),
      ),
    );
  }
}

/// A top card and the camera under it, with the screen's buttons hung
/// across the seam between them (SPEC.md decision 90): the main [button]
/// at the right, and a [leading] one (Pause, *Doesn't apply*) at the left,
/// on the same row.
///
/// The camera gets whatever height is left, so the buttons never move it:
/// with or without them, the two cards are laid out the same. The buttons
/// are laid out last, so they draw over both and take the touches there.
class SeamLayout extends StatelessWidget {
  const SeamLayout({
    super.key,
    required this.top,
    required this.camera,
    required this.gap,
    this.button,
    this.leading,
  });

  final Widget top;
  final Widget camera;
  final double gap;
  final Widget? button;

  /// A smaller button at the left, centred on the main button's row (where
  /// that row is, with or without the main button). It shrinks to fit
  /// beside the main button.
  final Widget? leading;

  /// Widest the button may be, as a share of the cards' width; longer words
  /// shrink to fit.
  static const maxWidthShare = 0.7;

  /// From the cards' edges to the buttons'.
  static const rightInset = 12.0;
  static const leftInset = 12.0;

  /// Width kept for the [leading] button beside the main one.
  static const leadingRoom = 120.0;

  /// The row's height: the main button with its shadow.
  static const rowHeight = SeamButton.height + 5;

  /// How far the button (shadow included) reaches into the camera, from its
  /// top edge: past the border, and no further than the chips at 12 pt
  /// inside it.
  static const cameraReach = 15.0;

  @override
  Widget build(BuildContext context) {
    final button = this.button;
    final leading = this.leading;
    return CustomMultiChildLayout(
      delegate: _SeamDelegate(gap),
      children: [
        LayoutId(id: _Seam.top, child: top),
        LayoutId(
          id: _Seam.camera,
          child: _ReportFloor(child: camera),
        ),
        if (leading != null)
          LayoutId(
            id: _Seam.leading,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: leading,
            ),
          ),
        if (button != null) LayoutId(id: _Seam.button, child: button),
      ],
    );
  }
}

/// How far down the screen a button on the seam can reach (from the top of
/// the view), while a [SeamLayout] is up; null otherwise. The Proof Panel
/// stays below it, so it never hides the button (SPEC.md decision 90). The
/// same with or without a button, so the panel doesn't move when one comes
/// or goes.
final seamButtonFloor = ValueNotifier<double?>(null);

/// Reports where the camera's top edge is on screen to [seamButtonFloor].
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
    final floor = localToGlobal(Offset.zero).dy + SeamLayout.cameraReach;
    if (floor == _sent) return;
    _sent = floor;
    // Not while painting: the panel rebuilds on the next frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached && _sent == floor) seamButtonFloor.value = floor;
    });
  }

  @override
  void detach() {
    final sent = _sent;
    _sent = null;
    super.detach();
    if (sent == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (seamButtonFloor.value == sent) seamButtonFloor.value = null;
    });
  }
}

enum _Seam { top, camera, leading, button }

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
    // The row's middle: the main button's, whether or not it's up.
    final rowCentre =
        cameraTop + SeamLayout.cameraReach - SeamLayout.rowHeight / 2;
    var buttonLeft = size.width - SeamLayout.rightInset;
    if (hasChild(_Seam.button)) {
      // With a button beside it, the main one leaves that one room: it
      // shrinks its words before the other gets too small to read.
      final room = hasChild(_Seam.leading)
          ? size.width -
                SeamLayout.leftInset -
                SeamLayout.rightInset -
                10 -
                SeamLayout.leadingRoom
          : double.infinity;
      final button = layoutChild(
        _Seam.button,
        BoxConstraints(
          maxWidth: math.max(
            0,
            math.min(size.width * SeamLayout.maxWidthShare, room),
          ),
        ),
      );
      buttonLeft -= button.width;
      positionChild(
        _Seam.button,
        Offset(buttonLeft, rowCentre - button.height / 2),
      );
    }
    if (hasChild(_Seam.leading)) {
      final leading = layoutChild(
        _Seam.leading,
        BoxConstraints(
          maxWidth: math.max(0, buttonLeft - 10 - SeamLayout.leftInset),
          maxHeight: SeamLayout.rowHeight,
        ),
      );
      positionChild(
        _Seam.leading,
        Offset(SeamLayout.leftInset, rowCentre - leading.height / 2),
      );
    }
  }

  @override
  bool shouldRelayout(_SeamDelegate old) => old.gap != gap;
}
