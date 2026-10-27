import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Serene Sacred Light Theme for Temple Lights companion app.
class AppTheme {
  AppTheme._();

  // === Surfaces (Serene Alabaster & Pure White) ===
  static const Color background = Color(0xFFF9F7F2);      // Sacred Ivory / Warm Alabaster
  static const Color surface = Color(0xFFFFFFFF);         // Pure Pristine White
  static const Color surfaceRaised = Color(0xFFF2ECE1);   // Warm Sand Stone
  static const Color surfaceGlow = Color(0xFFFFFBEB);     // Radiant Golden Glow Tint

  // === Borders ===
  static const Color border = Color(0xFFEAE4D6);          // Soft Sand Micro-border
  static const Color borderBright = Color(0xFFD8D0BF);    // Defined Warm Accent Border

  // === Sacred Accents ===
  static const Color amber = Color(0xFFD97706);           // Sacred Saffron Amber
  static const Color gold = Color(0xFFB45309);            // Deep Temple Gold
  static const Color warmWhite = Color(0xFFFEF3C7);       // Warm Amber Candle Wash
  static const Color cyan = Color(0xFF0284C7);            // Celestial Sky Azure
  static const Color green = Color(0xFF059669);           // Sacred Emerald Jade
  static const Color red = Color(0xFFDC2626);             // Temple Vermillion Red
  static const Color crimson = Color(0xFFDC2626);
  static const Color orange = Color(0xFFEA580C);          // Sacred Marigold Orange
  static const Color card = Color(0xFFFFFFFF);

  // === High-Contrast Readable Typography ===
  static const Color textPrimary = Color(0xFF1C1917);     // Deep Warm Obsidian
  static const Color textSecondary = Color(0xFF57534E);   // Warm Slate Granite
  static const Color textMuted = Color(0xFF8C867D);       // Soft Pebble Stone

  // === Typography Helpers ===
  static TextStyle heading({
    required double size,
    Color color = textPrimary,
    FontWeight weight = FontWeight.w700,
    double letterSpacing = 0.5,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.15,
      );

  static TextStyle body({
    required double size,
    Color color = textPrimary,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0.1,
  }) =>
      GoogleFonts.rubik(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.35,
      );

  static TextStyle mono({
    required double size,
    Color color = textPrimary,
    FontWeight weight = FontWeight.w600,
    double letterSpacing = 0.5,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: 1.15,
      );

  // === Light ThemeData Factory ===
  static ThemeData buildLight() {
    final base = ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        surface: surface,
        onSurface: textPrimary,
        primary: amber,
        onPrimary: Color(0xFFFFFFFF),
        secondary: gold,
        onSecondary: Color(0xFFFFFFFF),
        error: red,
        onError: Color(0xFFFFFFFF),
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.rubikTextTheme(base.textTheme).copyWith(
        displayLarge: heading(size: 40),
        displayMedium: heading(size: 32),
        headlineMedium: heading(size: 24),
        titleLarge: heading(size: 18),
        bodyLarge: body(size: 16),
        bodyMedium: body(size: 14),
        labelLarge: body(size: 12, weight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1.0),
        ),
      ),
    );
  }

  // === Dark Surfaces (Sacred Night & Warm Sandalwood) ===
  static const Color darkBackground = Color(0xFF141210);      // Deep Sacred Night
  static const Color darkSurface = Color(0xFF1F1B18);         // Sandalwood Stone
  static const Color darkSurfaceRaised = Color(0xFF2C2622);   // Carved Wood Altar
  static const Color darkBorder = Color(0xFF38312B);          // Muted Brass Border
  static const Color darkBorderBright = Color(0xFF4F453D);    // Soft Golden Rim
  static const Color darkTextPrimary = Color(0xFFF7F3EB);     // Radiant Ivory Cream
  static const Color darkTextSecondary = Color(0xFFB0A699);   // Warm Sandstone
  static const Color darkTextMuted = Color(0xFF7D7366);       // Deep Pebble

  // === Dark ThemeData Factory ===
  static ThemeData buildDark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        surface: darkSurface,
        onSurface: darkTextPrimary,
        primary: amber,
        onPrimary: Color(0xFFFFFFFF),
        secondary: gold,
        onSecondary: Color(0xFFFFFFFF),
        error: red,
        onError: Color(0xFFFFFFFF),
      ),
    );

    return base.copyWith(
      textTheme: GoogleFonts.rubikTextTheme(base.textTheme).copyWith(
        displayLarge: heading(size: 40, color: darkTextPrimary),
        displayMedium: heading(size: 32, color: darkTextPrimary),
        headlineMedium: heading(size: 24, color: darkTextPrimary),
        titleLarge: heading(size: 18, color: darkTextPrimary),
        bodyLarge: body(size: 16, color: darkTextPrimary),
        bodyMedium: body(size: 14, color: darkTextPrimary),
        labelLarge: body(size: 12, color: darkTextPrimary, weight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: darkTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1.0),
        ),
      ),
    );
  }
}
