import 'package:flutter/material.dart';

/// Design tokens from the Style B "70s game show" mockup (SPEC.md §3).
abstract final class SusColors {
  /// App background.
  static const mustard = Color(0xFFF2B33D);

  /// Text, borders, shadows, dark pills.
  static const ink = Color(0xFF2A160C);

  /// Cards, light buttons.
  static const cream = Color(0xFFFFF4DF);

  /// "Sus", pulse color, alerts. Only for graphics or text >= 24 px.
  static const tomato = Color(0xFFD9412B);

  /// "Legit", primary action buttons (cream text on teal).
  static const teal = Color(0xFF1F6F78);

  /// Deeper red (last step of the meter ramp) for surfaces that carry small
  /// cream text: cream on [tomato] is only ~4.1:1, on this ~5.5:1.
  static const tomatoDeep = Color(0xFFB8301D);

  /// "Hmm..." verdict board.
  static const brown = Color(0xFF8A4B1C);

  /// Marquee bulbs, face-guide oval.
  static const bulb = Color(0xFFFFE9A8);

  /// Empty meter blocks.
  static const unlit = Color(0xFFE8D9BC);

  /// 10-block applause meter ramp, low to high.
  static const meterRamp = <Color>[
    Color(0xFF1F6F78),
    Color(0xFF1F6F78),
    Color(0xFF3E8C7A),
    Color(0xFF8FAE5B),
    Color(0xFFE7C64A),
    Color(0xFFFFE9A8),
    Color(0xFFF08A4B),
    Color(0xFFE5683A),
    Color(0xFFD9412B),
    Color(0xFFB8301D),
  ];
}

abstract final class SusFonts {
  static const display = 'BowlbyOneSC';
  static const body = 'WorkSans';
}

abstract final class SusShape {
  static const borderWidth = 3.0;
  static const cardRadius = 20.0;
  static const buttonRadius = 16.0;
  static const pillRadius = 20.0;
  static const cameraRadius = 24.0;
  static const buttonHeight = 58.0;
  static const shadowOffset = Offset(0, 5);
  static const minTouch = 44.0;
}

abstract final class SusText {
  static TextStyle display(double size, {Color color = SusColors.ink}) =>
      TextStyle(
        fontFamily: SusFonts.display,
        fontSize: size,
        color: color,
        height: 1.05,
      );

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = SusColors.ink,
  }) => TextStyle(
    fontFamily: SusFonts.body,
    fontSize: size,
    fontWeight: weight,
    color: color,
  );

  static TextStyle label(double size, {Color color = SusColors.ink}) =>
      body(size, weight: FontWeight.w700, color: color);
}

ThemeData buildSusTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: SusFonts.body,
    scaffoldBackgroundColor: SusColors.mustard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: SusColors.teal,
      brightness: Brightness.light,
      primary: SusColors.teal,
      onPrimary: SusColors.cream,
      secondary: SusColors.tomato,
      surface: SusColors.cream,
      onSurface: SusColors.ink,
      error: SusColors.tomato,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: SusColors.ink,
      displayColor: SusColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SusColors.mustard,
      foregroundColor: SusColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? SusColors.cream : SusColors.ink,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? SusColors.teal : SusColors.unlit,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(SusColors.ink),
    ),
  );
}
