import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Pulse trend since the question started, against the player's calibrated
/// normal (dashed line).
///
/// The vertical scale is fixed at no less than ±[minHalfRange] BPM around
/// that normal, so a 2 BPM wobble stays small; an auto-scaled sparkline would
/// stretch noise to full height and look like a spike. Time runs left to
/// right over at least [minSpanMs], so the line draws itself across the first
/// seconds, then compresses. Gaps longer than [maxGapMs] (no confident
/// reading) break the line instead of joining across them.
class PulseSparkline extends StatelessWidget {
  const PulseSparkline({
    super.key,
    required this.points,
    required this.baseline,
    required this.fromMs,
    required this.nowMs,
    this.minHalfRange = 12,
    this.minSpanMs = 15000,
    this.maxGapMs = 4000,
  });

  /// (time ms, BPM), oldest first.
  final List<(int, double)> points;
  final double? baseline;
  final int fromMs;
  final int nowMs;
  final double minHalfRange;
  final int minSpanMs;
  final int maxGapMs;

  @override
  Widget build(BuildContext context) {
    // Decorative: the card's number and arrow say the same thing in words.
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.infinite,
        painter: SparklinePainter(
          points: points,
          baseline: baseline,
          fromMs: fromMs,
          nowMs: nowMs,
          minHalfRange: minHalfRange,
          minSpanMs: minSpanMs,
          maxGapMs: maxGapMs,
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  SparklinePainter({
    required this.points,
    required this.baseline,
    required this.fromMs,
    required this.nowMs,
    required this.minHalfRange,
    required this.minSpanMs,
    required this.maxGapMs,
  });

  final List<(int, double)> points;
  final double? baseline;
  final int fromMs;
  final int nowMs;
  final double minHalfRange;
  final int minSpanMs;
  final int maxGapMs;

  static const _stroke = 2.5;

  /// The vertical scale: (center BPM, half range BPM).
  (double, double) scale() {
    final center =
        baseline ??
        (points.isEmpty
            ? 0.0
            : points.map((p) => p.$2).reduce((a, b) => a + b) / points.length);
    var half = minHalfRange;
    for (final (_, v) in points) {
      half = math.max(half, (v - center).abs() * 1.15);
    }
    return (center, half);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (center, half) = scale();
    const pad = _stroke + 1;
    final span = math.max(nowMs - fromMs, minSpanMs).toDouble();
    double x(int t) => ((t - fromMs) / span).clamp(0.0, 1.0) * size.width;
    double y(double v) =>
        size.height / 2 - (v - center) / half * (size.height / 2 - pad);

    if (baseline != null) {
      final dash = Paint()
        ..color = SusColors.brown
        ..strokeWidth = 1.5;
      final by = y(center);
      for (var dx = 0.0; dx < size.width; dx += 7) {
        canvas.drawLine(
          Offset(dx, by),
          Offset(math.min(dx + 4, size.width), by),
          dash,
        );
      }
    }
    if (points.isEmpty) return;

    final line = Paint()
      ..color = SusColors.tomato
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    int? prevT;
    for (final (t, v) in points) {
      final o = Offset(x(t), y(v));
      if (prevT == null || t - prevT > maxGapMs) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
      prevT = t;
    }
    canvas.drawPath(path, line);
    final (lt, lv) = points.last;
    canvas.drawCircle(
      Offset(x(lt), y(lv)),
      3.5,
      Paint()..color = SusColors.tomato,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.nowMs != nowMs ||
      old.baseline != baseline ||
      old.points.length != points.length ||
      (points.isNotEmpty && old.points.last != points.last);
}
