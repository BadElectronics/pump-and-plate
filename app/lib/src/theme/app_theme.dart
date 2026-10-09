import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme(AppPalette p) {
  final brightness = p.isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: brightness,
  ).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    surface: p.surface,
    onSurface: p.text,
    outline: p.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Geist',
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: <ThemeExtension<dynamic>>[AppColors.fromPalette(p)],
  );
}

/// Shared text styles. Tabular figures keep numbers from jittering.
class AppText {
  static const _figures = [FontFeature.tabularFigures()];

  static TextStyle title(AppColors c) => TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.6,
        height: 1.15,
        color: c.text,
        fontFeatures: _figures,
      );

  static TextStyle body(AppColors c) => TextStyle(
        fontSize: 15,
        height: 1.5,
        color: c.text,
        fontFeatures: _figures,
      );

  static TextStyle quiet(AppColors c) => TextStyle(
        fontSize: 13,
        height: 1.45,
        color: c.muted,
        fontFeatures: _figures,
      );

  static TextStyle label(AppColors c) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: c.muted,
      );
}
