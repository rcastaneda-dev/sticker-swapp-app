import 'package:flutter/material.dart';

abstract final class SwappColors {
  // Brand primitives (for reference outside of ColorScheme contexts)
  static const Color navyBlue = Color(0xFF0A1F44);
  static const Color gold = Color(0xFFC89B3C);
  static const Color pitchGreen = Color(0xFF2E7D32);

  static ColorScheme get lightScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF0A1F44),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFD1E4FF),
        onPrimaryContainer: Color(0xFF001D36),
        secondary: Color(0xFFC89B3C),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFFFEABB),
        onSecondaryContainer: Color(0xFF3D2E00),
        tertiary: Color(0xFF2E7D32),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFC8E6C9),
        onTertiaryContainer: Color(0xFF003300),
        error: Color(0xFFBA1A1A),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFFFDAD6),
        onErrorContainer: Color(0xFF410002),
        surface: Color(0xFFF8F9FF),
        onSurface: Color(0xFF1A1C20),
        surfaceContainerHighest: Color(0xFFE0E2EC),
        outline: Color(0xFF74777F),
        outlineVariant: Color(0xFFC4C6D0),
        shadow: Color(0xFF000000),
        inverseSurface: Color(0xFF2F3036),
        onInverseSurface: Color(0xFFF0F0F7),
      );

  static ColorScheme get darkScheme => const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFFA0CAFF),
        onPrimary: Color(0xFF003258),
        primaryContainer: Color(0xFF0A1F44),
        onPrimaryContainer: Color(0xFFD1E4FF),
        secondary: Color(0xFFE8C868),
        onSecondary: Color(0xFF3D2E00),
        secondaryContainer: Color(0xFF584400),
        onSecondaryContainer: Color(0xFFFFEABB),
        tertiary: Color(0xFF81C784),
        onTertiary: Color(0xFF003300),
        tertiaryContainer: Color(0xFF1B5E20),
        onTertiaryContainer: Color(0xFFC8E6C9),
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        onErrorContainer: Color(0xFFFFDAD6),
        surface: Color(0xFF111318),
        onSurface: Color(0xFFE2E2E9),
        surfaceContainerHighest: Color(0xFF33353B),
        outline: Color(0xFF8E9099),
        outlineVariant: Color(0xFF44474F),
        shadow: Color(0xFF000000),
        inverseSurface: Color(0xFFE2E2E9),
        onInverseSurface: Color(0xFF2F3036),
      );
}
