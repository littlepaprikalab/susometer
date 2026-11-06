import 'dart:math' as math;

import 'package:flutter/material.dart';

/// What [FitText] gives up when even its smallest size doesn't fit.
enum FitOverflow {
  /// Keep the newest words of a live transcript: "…maybe once."
  keepEnd,

  /// Keep the beginning, ending in "…" (questions, hints).
  keepStart,
}

/// Text that fills a fixed-size box: it uses the largest of [sizes] that
/// fits, so the box never grows and the layout around it never moves. If
/// even the smallest size overflows, it shows whole lines only, trimmed per
/// [overflow].
class FitText extends StatelessWidget {
  const FitText(
    this.text, {
    super.key,
    required this.style,
    this.sizes = const [28, 24, 20, 17],
    this.textAlign,
    this.overflow = FitOverflow.keepEnd,
  }) : assert(sizes.length > 0);

  final String text;

  /// Builds the style for a given font size.
  final TextStyle Function(double size) style;

  /// Candidate font sizes, largest first.
  final List<double> sizes;

  final TextAlign? textAlign;
  final FitOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Measure exactly what Text will draw: it merges the ambient default
    // style (Material's body style sets a taller line height).
    final ambient = DefaultTextStyle.of(context);
    TextStyle styled(double size) => ambient.style.merge(style(size));
    return LayoutBuilder(
      builder: (context, constraints) {
        TextPainter painter(String t, TextStyle s) => TextPainter(
          text: TextSpan(text: t, style: s),
          textAlign: textAlign ?? TextAlign.start,
          textDirection: direction,
          textScaler: scaler,
          textHeightBehavior: ambient.textHeightBehavior,
        )..layout(maxWidth: constraints.maxWidth);

        bool fits(String t, TextStyle s) {
          final p = painter(t, s);
          final ok = p.height <= constraints.maxHeight;
          p.dispose();
          return ok;
        }

        for (final size in sizes) {
          final s = styled(size);
          if (fits(text, s)) return Text(text, style: s, textAlign: textAlign);
        }

        final s = styled(sizes.last);
        if (overflow == FitOverflow.keepStart) {
          final line = painter('Ag', s);
          final lines = math.max(1, constraints.maxHeight ~/ line.height);
          line.dispose();
          return ClipRect(
            child: Text(
              text,
              style: s,
              textAlign: textAlign,
              maxLines: lines,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        // Drop the fewest leading words so "…" plus the rest fits.
        final words = text.split(' ');
        String tail(int dropped) => '…${words.skip(dropped).join(' ')}';
        var lo = 1;
        var hi = math.max(1, words.length - 1);
        while (lo < hi) {
          final mid = (lo + hi) ~/ 2;
          if (fits(tail(mid), s)) {
            hi = mid;
          } else {
            lo = mid + 1;
          }
        }
        // VoiceOver still reads the whole text, not the trimmed tail.
        return Semantics(
          label: text,
          excludeSemantics: true,
          child: ClipRect(
            child: Text(tail(lo), style: s, textAlign: textAlign),
          ),
        );
      },
    );
  }
}
