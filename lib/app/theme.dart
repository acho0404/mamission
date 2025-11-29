import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 🎨 Thème Premium MaMission
/// Basé sur la police 'Plus Jakarta Sans' et une esthétique Soft UI.

// --- PALETTE DE COULEURS ---
const Color kPrimaryColor = Color(0xFF6C63FF);      // Violet Principal
const Color kSecondaryColor = Color(0xFF9381FF);    // Lavande
const Color kAccentColor = Color(0xFFF4F2FF);       // Violet très pâle (Fonds boutons)
const Color kTextPrimary = Color(0xFF1A1A1A);       // Noir doux
const Color kTextSecondary = Color(0xFF8E8E93);     // Gris iOS
const Color kBackgroundLight = Color(0xFFFAFAFA);   // Blanc cassé (Clean)
const Color kSurfaceWhite = Colors.white;
const Color kErrorColor = Color(0xFFFF6B6B);

// Nom de la font utilisée
const String kFontFamily = 'Plus Jakarta Sans';

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: kFontFamily,

    // --- COULEURS ---
    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      primary: kPrimaryColor,
      secondary: kSecondaryColor,
      surface: kSurfaceWhite,
      error: kErrorColor,
      brightness: Brightness.light,
    ),

    scaffoldBackgroundColor: kBackgroundLight,

    // --- TYPOGRAPHIE ---
    textTheme: const TextTheme(
      // Gros titres type "LA MISSION"
      displaySmall: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w900,   // ⬅ Aligné sur ta page mission
        color: kTextPrimary,
        letterSpacing: -1.0,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: kTextPrimary,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
        letterSpacing: -0.3,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: kTextPrimary,
        letterSpacing: -0.2,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: kTextPrimary,
        height: 1.4,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: kTextSecondary,
        height: 1.4,
      ),
      // Labels type "CATÉGORIE", "HORAIRE" etc.
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,   // ⬅ Comme dans La mission
        color: kTextSecondary,
      ),
    ),

    // --- APP BAR ---
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackgroundLight,
      foregroundColor: kTextPrimary,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
      ),
      iconTheme: IconThemeData(color: kTextPrimary),
    ),

    // --- INPUTS ---
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFEAEAEA), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kPrimaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kErrorColor, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kErrorColor, width: 2),
      ),
      hintStyle: TextStyle(
        color: Colors.grey.shade400,
        fontWeight: FontWeight.w500,
        fontSize: 15,
      ),
    ),

    // --- BOUTONS ---
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimaryColor,
        side: const BorderSide(color: kPrimaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    // --- CARDS (Correction: CardThemeData) ---
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFF0F0F0), width: 1),
      ),
    ),

    // --- CHIPS ---
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF4F4F6),
      disabledColor: Colors.grey.shade200,
      selectedColor: kPrimaryColor,
      secondarySelectedColor: kPrimaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: const TextStyle(
        color: kTextSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        fontFamily: kFontFamily,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        fontFamily: kFontFamily,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide.none,
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0xFFEEEEEE),
      thickness: 1,
      space: 1,
    ),
  );
}

// --- DARK THEME ---
ThemeData buildDarkTheme() {
  const kBgDark = Color(0xFF121212);
  const kSurfaceDark = Color(0xFF1E1E1E);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: kFontFamily,

    colorScheme: ColorScheme.fromSeed(
      seedColor: kPrimaryColor,
      brightness: Brightness.dark,
      primary: kPrimaryColor,
      surface: kSurfaceDark,
      background: kBgDark,
    ),

    scaffoldBackgroundColor: kBgDark,

    appBarTheme: const AppBarTheme(
      backgroundColor: kBgDark,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: kFontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),

    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        letterSpacing: -1.0,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white70,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.grey,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2C2C2E),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
      ),
      hintStyle: TextStyle(color: Colors.grey.shade600),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),

    // Correction: CardThemeData
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E1E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
    ),
  );
}
