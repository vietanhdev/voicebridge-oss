import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// VoiceBridge palette — industrial-dark with a teal accent and safety amber.
class AppColors {
  static const seed = Color(0xFF00BFA6);
  static const bg = Color(0xFF0B0E13);
  static const surface = Color(0xFF151B24);
  static const surfaceAlt = Color(0xFF1E2733);
  static const accent = Color(0xFF1FE3C2);
  static const accent2 = Color(0xFF4D8BFF);
  static const amber = Color(0xFFFFB300); // safety / glossary
  static const danger = Color(0xFFFF5C5C);
  static const textHi = Color(0xFFF3F6FA);
  static const textLo = Color(0xFF94A0B0);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.surface,
    primary: AppColors.accent,
    secondary: AppColors.accent2,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.textHi, displayColor: AppColors.textHi),
  );
}
