import 'package:flutter/material.dart';

/// One color theme. Every color in the app comes from one of these.
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.isDark,
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.chip,
    required this.protein,
    required this.ringA,
    required this.ringB,
  });

  final String id;
  final String name;
  final bool isDark;
  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color chip;
  final Color protein;

  /// The two colours the Home rings blend with the accent.
  final Color ringA;
  final Color ringB;

  static const earth = AppPalette(
    id: 'earth',
    name: 'Earth',
    isDark: false,
    background: Color(0xFFF2EEE6),
    surface: Color(0xFFFAF8F4),
    text: Color(0xFF1F1C17),
    muted: Color(0xFF6A6257),
    line: Color(0xFFE3DCD0),
    accent: Color(0xFF4D6A3C),
    onAccent: Color(0xFFFFFFFF),
    chip: Color(0xFFE9E3D8),
    protein: Color(0xFFA9562F),
    ringA: Color(0xFFC9A45C),
    ringB: Color(0xFFB5562E),
  );

  static const clay = AppPalette(
    id: 'clay',
    name: 'Clay',
    isDark: false,
    background: Color(0xFFF4ECE2),
    surface: Color(0xFFFBF6F0),
    text: Color(0xFF2A1E16),
    muted: Color(0xFF725F51),
    line: Color(0xFFE8DCCD),
    accent: Color(0xFFA9562F),
    onAccent: Color(0xFFFFFFFF),
    chip: Color(0xFFEDE2D5),
    protein: Color(0xFF4D6A3C),
    ringA: Color(0xFFD9A066),
    ringB: Color(0xFF6E8B4E),
  );

  static const stone = AppPalette(
    id: 'stone',
    name: 'Stone',
    isDark: false,
    background: Color(0xFFECEDEA),
    surface: Color(0xFFF7F8F6),
    text: Color(0xFF1B1D1B),
    muted: Color(0xFF5E625E),
    line: Color(0xFFDADDD8),
    accent: Color(0xFF3F5F66),
    onAccent: Color(0xFFFFFFFF),
    chip: Color(0xFFE2E4E0),
    protein: Color(0xFFA9562F),
    ringA: Color(0xFF7FA3AA),
    ringB: Color(0xFFC9A45C),
  );

  static const night = AppPalette(
    id: 'night',
    name: 'Night',
    isDark: true,
    background: Color(0xFF171512),
    surface: Color(0xFF221F1B),
    text: Color(0xFFEDE7DD),
    muted: Color(0xFFA39A8C),
    line: Color(0xFF34302A),
    accent: Color(0xFF9DB383),
    onAccent: Color(0xFF171512),
    chip: Color(0xFF2C2823),
    protein: Color(0xFFD9896A),
    ringA: Color(0xFFC9A45C),
    ringB: Color(0xFFD9896A),
  );

  /// Optional deep green and blue theme (matches the app icon).
  static const emerald = AppPalette(
    id: 'emerald',
    name: 'Emerald',
    isDark: true,
    background: Color(0xFF0B4436),
    surface: Color(0xFF105442),
    text: Color(0xFFEEF8F3),
    muted: Color(0xFFA9D2C3),
    line: Color(0xFF24705A),
    accent: Color(0xFF5DB8FF),
    onAccent: Color(0xFF04213A),
    chip: Color(0xFF0A3A2E),
    protein: Color(0xFFFFC07A),
    ringA: Color(0xFF36C9A0),
    ringB: Color(0xFF9BEBCB),
  );

  static const all = <AppPalette>[earth, clay, stone, night, emerald];

  static AppPalette byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => earth);
}

/// The palette attached to the app's theme. Because it can interpolate,
/// switching themes fades every color smoothly instead of snapping.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.chip,
    required this.protein,
    required this.ringA,
    required this.ringB,
  });

  factory AppColors.fromPalette(AppPalette p) => AppColors(
        background: p.background,
        surface: p.surface,
        text: p.text,
        muted: p.muted,
        line: p.line,
        accent: p.accent,
        onAccent: p.onAccent,
        chip: p.chip,
        protein: p.protein,
        ringA: p.ringA,
        ringB: p.ringB,
      );

  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color line;
  final Color accent;
  final Color onAccent;
  final Color chip;
  final Color protein;
  final Color ringA;
  final Color ringB;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? muted,
    Color? line,
    Color? accent,
    Color? onAccent,
    Color? chip,
    Color? protein,
    Color? ringA,
    Color? ringB,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      chip: chip ?? this.chip,
      protein: protein ?? this.protein,
      ringA: ringA ?? this.ringA,
      ringB: ringB ?? this.ringB,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      protein: Color.lerp(protein, other.protein, t)!,
      ringA: Color.lerp(ringA, other.ringA, t)!,
      ringB: Color.lerp(ringB, other.ringB, t)!,
    );
  }
}
