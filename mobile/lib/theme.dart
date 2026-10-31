import 'package:flutter/material.dart';

/// High contrast, large text (>= 20sp), large tap targets (>= 56dp) - PRD F1.
class AppTheme {
  static const minTap = 64.0; // above the 56dp minimum

  static ThemeData build(String lang) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5D3B), brightness: Brightness.light)
          .copyWith(surface: Colors.white, onSurface: const Color(0xFF111111)),
      scaffoldBackgroundColor: const Color(0xFFF7F5EF),
    );
    // Noto Nastaliq Urdu is the most readable Urdu face if installed on the device; system font otherwise.
    final family = lang == 'ur' ? 'Noto Nastaliq Urdu' : null;
    final text = base.textTheme.apply(fontFamily: family, bodyColor: const Color(0xFF111111)).copyWith(
          bodyLarge: TextStyle(fontSize: 22, fontFamily: family, height: lang == 'ur' ? 1.9 : 1.35),
          bodyMedium: TextStyle(fontSize: 20, fontFamily: family, height: lang == 'ur' ? 1.9 : 1.35),
          titleLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, fontFamily: family),
          headlineSmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, fontFamily: family),
          labelLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFamily: family),
        );
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF0B5D3B),
        foregroundColor: Colors.white,
        titleTextStyle: text.titleLarge?.copyWith(color: Colors.white),
        toolbarHeight: 68,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(minTap, minTap),
          textStyle: text.labelLarge,
          backgroundColor: const Color(0xFF0B5D3B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTap, minTap),
          textStyle: text.labelLarge,
          foregroundColor: const Color(0xFF0B5D3B),
          side: const BorderSide(color: Color(0xFF0B5D3B), width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(minTap, minTap), textStyle: text.labelLarge),
      ),
      switchTheme: const SwitchThemeData(materialTapTargetSize: MaterialTapTargetSize.padded),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelStyle: const TextStyle(fontSize: 20),
      ),
    );
  }
}
