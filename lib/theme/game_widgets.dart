import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fit_text.dart';
import 'tokens.dart';

/// Mustard page with the mockup's 18 px side padding.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, defaultBottomPadding),
    this.background = SusColors.mustard,
  });

  final Widget child;
  static const defaultBottomPadding = 16.0;

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
  const HostBubble({
    super.key,
    required this.text,
    this.fontSize = 20,
    this.singleLine = false,
    this.lines,
    this.minFontSize = 16,
  });

  final String text;
  final double fontSize;

  /// One line that shrinks to fit, so the bubble's height never changes.
  final bool singleLine;

  /// Always this many full-size lines tall: shorter text sits in the middle,
  /// longer text shrinks to fit, so the bubble's height never changes.
  final int? lines;

  /// With [lines]: the smallest size the text shrinks to, 2 pt at a time.
  final double minFontSize;

  double _lineHeight(BuildContext context) {
    final ambient = DefaultTextStyle.of(context);
    final painter = TextPainter(
      text: TextSpan(
        text: 'Ag',
        style: ambient.style.merge(SusText.display(fontSize)),
      ),
      textHeightBehavior: ambient.textHeightBehavior,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final h = painter.height;
    painter.dispose();
    return h;
  }

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
              child: singleLine
                  ? SizedBox(
                      // Height of one full-size line, so a long line that
                      // shrinks to fit doesn't make the bubble shorter.
                      height: _lineHeight(context),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          text,
                          maxLines: 1,
                          style: SusText.display(fontSize),
                        ),
                      ),
                    )
                  : lines != null
                  ? SizedBox(
                      height: _lineHeight(context) * lines!,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FitText(
                          text,
                          sizes: [
                            for (
                              var size = fontSize;
                              size >= minFontSize;
                              size -= 2
                            )
                              size,
                          ],
                          overflow: FitOverflow.keepStart,
                          style: SusText.display,
                        ),
                      ),
                    )
                  : Text(text, style: SusText.display(fontSize)),
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
///
/// The bars jump to each new level rather than animate to it. The level
/// changes every 100 ms while anyone makes a sound, so a 90 ms animation
/// never stopped, and the screen around it, camera and all, was redrawn on
/// every vsync (60–120 times a second) instead of 10. Those frames compete
/// with the camera preview for the iOS main thread.
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
              Container(
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

  /// Height of a chip at the current text size, for layouts that must keep
  /// clear of it (the face oval).
  static double heightFor(BuildContext context, {double fontSize = 12}) {
    // Called on every camera update; it only changes with the text size.
    final scaler = MediaQuery.textScalerOf(context);
    final key = (scaler.scale(100), fontSize);
    return _heights[key] ??= _measure(context, fontSize);
  }

  static final _heights = <(double, double), double>{};

  static double _measure(BuildContext context, double fontSize) {
    final ambient = DefaultTextStyle.of(context);
    final painter = TextPainter(
      text: TextSpan(
        text: 'Ag',
        style: ambient.style.merge(SusText.label(fontSize)),
      ),
      textHeightBehavior: ambient.textHeightBehavior,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final h = math.max(painter.height, 14.0) + 10;
    painter.dispose();
    return h;
  }

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
      onTap: onPressed,
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

/// Pulse waveform drawn from the SDK's arterial pressure trace, by time:
/// the card's width is always [windowMs], newest sample at the right edge
/// (SPEC.md decision 88). Until the first [windowMs] has arrived, the line
/// draws itself from the left. Samples more than [maxGapMs] apart aren't
/// joined, so missing waveform shows as a gap instead of a made-up beat.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.points,
    required this.windowMs,
    required this.maxGapMs,
    this.color = SusColors.tomato,
  });

  /// (time ms, value), oldest first. Any clock: only differences are used.
  final List<(double, double)> points;
  final int windowMs;
  final int maxGapMs;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live pulse waveform',
      excludeSemantics: true,
      child: CustomPaint(
        size: Size.infinite,
        painter: WaveformLinePainter(
          List.of(points),
          color,
          windowMs: windowMs,
          maxGapMs: maxGapMs,
        ),
      ),
    );
  }
}

class WaveformLinePainter extends CustomPainter {
  WaveformLinePainter(
    this.points,
    this.color, {
    required this.windowMs,
    required this.maxGapMs,
    this.strokeWidth = 3.5,
  });

  final List<(double, double)> points;
  final Color color;
  final int windowMs;
  final int maxGapMs;
  final double strokeWidth;

  /// The line in [size], in pieces split at gaps. A piece can start left of
  /// the edge (the sample just before the window); [paint] clips it.
  List<List<Offset>> segments(Size size) {
    if (points.length < 2 || windowMs <= 0) return const [];
    final end = points.last.$1;
    final start = math.max(points.first.$1, end - windowMs);
    var lo = points.first.$2;
    var hi = lo;
    for (final (_, v) in points) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final range = math.max(hi - lo, 1e-6);
    final pad = strokeWidth;
    final out = <List<Offset>>[];
    double? prev;
    for (final (t, v) in points) {
      final o = Offset(
        (t - start) / windowMs * size.width,
        pad + (size.height - 2 * pad) * (1 - (v - lo) / range),
      );
      if (prev == null || t - prev > maxGapMs) {
        out.add([o]);
      } else {
        out.last.add(o);
      }
      prev = t;
    }
    return [
      for (final s in out)
        if (s.length > 1) s,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lines = segments(size);
    if (lines.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        Paint()
          ..color = SusColors.unlit
          ..strokeWidth = 2,
      );
      return;
    }
    final path = Path();
    for (final line in lines) {
      path.moveTo(line.first.dx, line.first.dy);
      for (final o in line.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WaveformLinePainter old) =>
      old.color != color ||
      old.windowMs != windowMs ||
      old.maxGapMs != maxGapMs ||
      old.strokeWidth != strokeWidth ||
      old.points.length != points.length ||
      (points.isNotEmpty &&
          (old.points.first != points.first || old.points.last != points.last));
}

/// Live reading card along the bottom of the camera (Calibrate, Ask,
/// Answer): label and value, an optional small chart, and an optional change
/// against the player's normal.
class LiveStatCard extends StatelessWidget {
  const LiveStatCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.trend,
    this.trailing,
  });

  static const height = 48.0;

  /// Inset from the camera's edges.
  static const inset = 10.0;

  /// With a chart, the most of the card's inside the label and number may
  /// take before they shrink.
  static const textMaxShare = 0.4;

  /// With a chart, the most [trailing] may take before it shrinks.
  static const trailingMaxShare = 0.3;

  final String label;
  final String value;
  final double? delta;

  /// Optional small chart between the number and the arrow.
  final Widget? trend;

  /// Optional status at the right end, e.g. "Sam talking".
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final text = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: SusText.body(11, weight: FontWeight.w600),
            ),
          ),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: SusText.body(16, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: SusColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SusColors.ink, width: 2.5),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            if (trend == null)
              Expanded(child: text)
            else ...[
              // The words keep their own width and the chart takes all the
              // rest (SPEC.md decision 88). Past [textMaxShare] of the card
              // the words shrink instead, so a long number or large text
              // can't squeeze the chart out.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: box.maxWidth * textMaxShare,
                ),
                child: text,
              ),
              const SizedBox(width: 8),
              Expanded(child: SizedBox(height: 30, child: trend)),
            ],
            if (d != null && d.round() != 0) ...[
              Icon(
                d > 0
                    ? Icons.arrow_drop_up_rounded
                    : Icons.arrow_drop_down_rounded,
                color: d > 0 ? SusColors.tomato : SusColors.teal,
                size: 22,
              ),
              Text(
                '${d.abs().round()}',
                style: SusText.body(14, weight: FontWeight.w700),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 6),
              if (trend == null)
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: box.maxWidth * trailingMaxShare,
                  ),
                  child: FittedBox(fit: BoxFit.scaleDown, child: trailing),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What to do about a camera problem, in the live cards' row while the
/// reading is paused (their numbers are frozen then). Same row, so nothing
/// runs into the face oval. VoiceOver hears it with the problem's stamp
/// (SPEC.md decision 69), so it isn't read twice.
class PausedFixRow extends StatelessWidget {
  const PausedFixRow(this.fix, {super.key});

  final String fix;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: LiveStatCard.height,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ExcludeSemantics(
            child: DotChip(label: fix, dot: SusColors.mustard, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

/// Where the face oval must stay clear of: chips along the top (at 12 pt)
/// and live cards along the bottom.
EdgeInsets cameraGuideClear(BuildContext context) => EdgeInsets.only(
  top: 12 + DotChip.heightFor(context) + 4,
  bottom: LiveStatCard.inset + LiveStatCard.height + 4,
);
