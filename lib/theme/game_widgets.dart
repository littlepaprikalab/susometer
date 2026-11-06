import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Mustard page with the mockup's 18 px side padding.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 16),
    this.background = SusColors.mustard,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// The host: an ink circle with a speaker icon and a cream speech bubble.
/// The text doubles as captions for the host's voice.
class HostBubble extends StatelessWidget {
  const HostBubble({super.key, required this.text, this.fontSize = 20});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Host says: $text',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: SusColors.ink,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: SusColors.mustard,
              size: 26,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: SusColors.cream,
                border: Border.all(
                  color: SusColors.ink,
                  width: SusShape.borderWidth,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child: Text(text, style: SusText.display(fontSize)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of marquee bulbs. With [flash], alternate bulbs blink.
class BulbRow extends StatelessWidget {
  const BulbRow({
    super.key,
    this.count = 12,
    this.size = 12,
    this.colorAt,
    this.phase = 0,
  });

  final int count;
  final double size;
  final Color Function(int i)? colorAt;

  /// Animation phase for flashing (0 or 1 alternates bulbs).
  final int phase;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color:
                    colorAt?.call(i) ??
                    ((i + phase).isEven || phase == 0
                        ? SusColors.bulb
                        : const Color(0xFF8A7A5A)),
                shape: BoxShape.circle,
                border: Border.all(color: SusColors.ink, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bulb-framed board with a hard ink drop shadow (logo, scoreboard).
class MarqueeBoard extends StatelessWidget {
  const MarqueeBoard({
    super.key,
    required this.color,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 14),
    this.bulbColorAt,
    this.radius = 26,
  });

  final Color color;
  final Widget child;
  final EdgeInsets padding;
  final Color Function(int i)? bulbColorAt;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: SusColors.ink, width: SusShape.borderWidth),
        boxShadow: const [
          BoxShadow(color: SusColors.ink, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BulbRow(colorAt: bulbColorAt),
          child,
          BulbRow(colorAt: bulbColorAt),
        ],
      ),
    );
  }
}

/// 10-block applause meter, ramp colors low→high (SPEC.md §3).
class ApplauseMeter extends StatelessWidget {
  const ApplauseMeter({super.key, required this.score, this.height = 30});

  final int score;
  final double height;

  @override
  Widget build(BuildContext context) {
    final lit = (score / 10).round().clamp(0, 10);
    return Semantics(
      label: 'Applause meter: $lit of 10 lit',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 10; i++)
            Expanded(
              child: Container(
                height: height,
                margin: EdgeInsets.only(right: i == 9 ? 0 : 5),
                decoration: BoxDecoration(
                  color: i < lit ? SusColors.meterRamp[i] : SusColors.unlit,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SusColors.ink, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Little level bars (mic or talking indicator).
class LevelBars extends StatelessWidget {
  const LevelBars({
    super.key,
    required this.level,
    this.color = SusColors.teal,
    this.count = 8,
    this.maxHeight = 20,
    this.barWidth = 4,
  });

  final double level;
  final Color color;
  final int count;
  final double maxHeight;
  final double barWidth;

  static const _shape = [0.45, 0.75, 1.0, 0.6, 0.9, 1.0, 0.5, 0.7];

  @override
  Widget build(BuildContext context) {
    final l = level.clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: SizedBox(
        height: maxHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: barWidth,
                height: math.max(3, maxHeight * l * _shape[i % _shape.length]),
                margin: EdgeInsets.only(right: i == count - 1 ? 0 : 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Question 2 of 5" dots.
class ProgressDots extends StatelessWidget {
  const ProgressDots({super.key, required this.total, required this.filled});

  final int total;
  final int filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Question $filled of $total',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 14,
              height: 14,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
              decoration: BoxDecoration(
                color: i < filled ? SusColors.bulb : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: SusColors.ink, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cream pill with a colored status dot (camera chips, statuses).
class DotChip extends StatelessWidget {
  const DotChip({
    super.key,
    required this.label,
    required this.dot,
    this.outlined = false,
    this.fontSize = 12,
    this.leading,
  });

  final String label;
  final Color dot;
  final bool outlined;
  final double fontSize;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: outlined ? Border.all(color: SusColors.ink, width: 2) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading ??
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
          const SizedBox(width: 6),
          Text(label, style: SusText.label(fontSize)),
        ],
      ),
    );
  }
}

/// Stat tile on the Verdict screen.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: SusText.display(21)),
          ),
          Text(label, style: SusText.body(12, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Teal initial circle for a contestant.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initial, this.size = 36});

  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SusColors.teal,
        shape: BoxShape.circle,
        border: Border.all(color: SusColors.ink, width: 2),
      ),
      child: Text(
        initial,
        style: SusText.display(size * 0.44, color: SusColors.cream),
      ),
    );
  }
}

/// 88 px ink circle with an icon (E2, E5).
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.size = 88});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: SusColors.ink,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: SusColors.mustard, size: size * 0.48),
    );
  }
}

/// Small cream pause button with a hard shadow.
class PauseButton extends StatelessWidget {
  const PauseButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pause the game',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 56,
          height: 48,
          decoration: BoxDecoration(
            color: SusColors.cream,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SusColors.ink, width: 2.5),
            boxShadow: const [
              BoxShadow(color: SusColors.ink, offset: Offset(0, 3)),
            ],
          ),
          child: const Icon(Icons.pause_rounded, color: SusColors.ink),
        ),
      ),
    );
  }
}

/// Dashed-outline button ("Too loud? Tap when done asking").
class DashedButton extends StatelessWidget {
  const DashedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: CustomPaint(
          painter: const _DashedBorderPainter(radius: 14),
          child: SizedBox(
            height: height,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: SusText.body(15, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SusColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(1.25);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 8), paint);
        d += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}

/// Cream rounded card used for bottom sheets (E6, Pause).
class SheetCard extends StatelessWidget {
  const SheetCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            color: SusColors.cream,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: SusColors.ink,
              width: SusShape.borderWidth,
            ),
            boxShadow: const [
              BoxShadow(color: SusColors.ink, offset: Offset(0, 6)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Ink pill like "Sam's in the hot seat".
class HotSeatPill extends StatelessWidget {
  const HotSeatPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: SusColors.ink,
        borderRadius: BorderRadius.circular(SusShape.pillRadius),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: SusText.body(
          14,
          weight: FontWeight.w700,
          color: SusColors.mustard,
        ),
      ),
    );
  }
}

/// Pulse waveform drawn from the SDK's arterial pressure trace.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.samples,
    this.color = SusColors.tomato,
  });

  final List<double> samples;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live pulse waveform',
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.infinite,
        painter: WaveformLinePainter(List.of(samples), color),
      ),
    );
  }
}

class WaveformLinePainter extends CustomPainter {
  WaveformLinePainter(this.samples, this.color, {this.strokeWidth = 3.5});

  final List<double> samples;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        Paint()
          ..color = SusColors.unlit
          ..strokeWidth = 2,
      );
      return;
    }
    var lo = samples.first;
    var hi = samples.first;
    for (final v in samples) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final range = math.max(hi - lo, 1e-6);
    final pad = strokeWidth;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = size.width * i / (samples.length - 1);
      final y = pad + (size.height - 2 * pad) * (1 - (samples[i] - lo) / range);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformLinePainter oldDelegate) => true;
}
