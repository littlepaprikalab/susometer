import 'package:flutter/material.dart';

import 'tokens.dart';

/// Chunky game-show button: 3px ink border, radius 16, hard 0/5 ink shadow.
/// Presses down onto its shadow.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = SusColors.teal,
    this.textColor = SusColors.cream,
    this.height = SusShape.buttonHeight,
    this.fontSize = 17,
    this.expand = true,
    this.showLabel = true,
  });

  /// Light variant: cream fill, ink text.
  const ChunkyButton.light({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = SusShape.buttonHeight,
    this.fontSize = 17,
    this.expand = true,
    this.showLabel = true,
  }) : color = SusColors.cream,
       textColor = SusColors.ink;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final double height;
  final double fontSize;
  final bool expand;

  /// False for an icon-only button; [label] is then only for accessibility.
  final bool showLabel;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final pressed = _down && enabled;
    final shadow = SusShape.shadowOffset.dy;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, color: widget.textColor, size: widget.fontSize + 5),
          if (widget.showLabel) const SizedBox(width: 8),
        ],
        if (widget.showLabel)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                maxLines: 1,
                style: SusText.body(
                  widget.fontSize,
                  weight: FontWeight.w700,
                  color: widget.textColor,
                ),
              ),
            ),
          ),
      ],
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
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: SizedBox(
            height: widget.height + shadow,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: shadow,
                  height: widget.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: SusColors.ink,
                      borderRadius: BorderRadius.circular(
                        SusShape.buttonRadius,
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 60),
                  left: 0,
                  right: 0,
                  top: pressed ? shadow : 0,
                  height: widget.height,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.showLabel ? 12 : 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(
                        SusShape.buttonRadius,
                      ),
                      border: Border.all(
                        color: SusColors.ink,
                        width: SusShape.borderWidth,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cream card with a 3px ink border.
class SusCard extends StatelessWidget {
  const SusCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = SusColors.cream,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(SusShape.cardRadius),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
      ),
      child: child,
    );
  }
}

/// Rounded pill. Default: ink fill, mustard text.
class SusPill extends StatelessWidget {
  const SusPill({
    super.key,
    required this.label,
    this.icon,
    this.color = SusColors.ink,
    this.textColor = SusColors.mustard,
    this.fontSize = 13,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(SusShape.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: textColor),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: SusText.body(
                fontSize,
                weight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round ink-bordered icon button (back, gear). 48x48 touch target.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        onTap: onPressed,
        child: InkResponse(
          onTap: onPressed,
          radius: 28,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: SusColors.cream,
              shape: BoxShape.circle,
              border: Border.all(
                color: SusColors.ink,
                width: SusShape.borderWidth,
              ),
            ),
            child: Icon(icon, color: SusColors.ink, size: 24),
          ),
        ),
      ),
    );
  }
}
