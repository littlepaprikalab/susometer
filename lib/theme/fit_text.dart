import 'package:flutter/material.dart';

/// Text that fills a fixed-size box: it uses the largest of [sizes] that
/// fits, so the box never grows and the layout around it never moves. If
/// even the smallest size overflows, it keeps the end of the text visible
/// (the newest words of a live transcript) and clips the start.
class FitText extends StatelessWidget {
  const FitText(
    this.text, {
    super.key,
    required this.style,
    this.sizes = const [28, 24, 20, 17],
    this.textAlign,
  });

  final String text;

  /// Builds the style for a given font size.
  final TextStyle Function(double size) style;

  /// Candidate font sizes, largest first.
  final List<double> sizes;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        bool fits(TextStyle s) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: s),
            textAlign: textAlign ?? TextAlign.start,
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: constraints.maxWidth);
          final ok = painter.height <= constraints.maxHeight;
          painter.dispose();
          return ok;
        }

        for (final size in sizes) {
          final s = style(size);
          if (fits(s)) return Text(text, style: s, textAlign: textAlign);
        }
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.bottomLeft,
            minHeight: 0,
            maxHeight: double.infinity,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Text(text, style: style(sizes.last), textAlign: textAlign),
            ),
          ),
        );
      },
    );
  }
}
