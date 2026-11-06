import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:susometer/theme/tokens.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // Pairs the app uses for small text (< 24 px) must reach WCAG AA 4.5:1.
  final smallText = {
    'ink on mustard': (SusColors.ink, SusColors.mustard),
    'ink on cream': (SusColors.ink, SusColors.cream),
    'cream on teal (buttons)': (SusColors.cream, SusColors.teal),
    'mustard on ink (pills)': (SusColors.mustard, SusColors.ink),
    'cream on brown (Hmm… badge)': (SusColors.cream, SusColors.brown),
    'cream on tomatoDeep (Sus badge, vote chip)': (
      SusColors.cream,
      SusColors.tomatoDeep,
    ),
    'brown hint on cream': (SusColors.brown, SusColors.cream),
    'cream on ink (house rule, proof panel)': (SusColors.cream, SusColors.ink),
  };
  for (final e in smallText.entries) {
    test('${e.key} ≥ 4.5:1', () {
      expect(contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5));
    });
  }

  test('cream on tomato is only for large text (≥ 3:1)', () {
    final c = contrast(SusColors.cream, SusColors.tomato);
    expect(c, greaterThanOrEqualTo(3.0));
    expect(c, lessThan(4.5), reason: 'which is why small text uses tomatoDeep');
  });
}
