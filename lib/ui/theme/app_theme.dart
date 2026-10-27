import 'package:flutter/material.dart';

/// Navy, orange and gold from the selected DawnMesh mark.
class AppTheme {
  static const brandNavy = Color(0xFF080F39);
  static const brandIndigo = Color(0xFF202B58);
  static const brandOrange = Color(0xFFFF7446);
  static const brandGold = Color(0xFFFFD587);
  static const warmWhite = Color(0xFFFFF3DC);

  static const lightPrimary = brandNavy;
  static const lightAccent = Color(0xFFBB4721);
  static const lightBg = Color(0xFFFFF8EF);
  static const lightCardBg = Color(0xFFFFFFFF);
  static const lightTextPrimary = Color(0xFF17213F);
  static const lightTextSecondary = Color(0xFF58617A);
  static const lightOutline = Color(0xFFD9DCE6);
  static const lightDanger = Color(0xFFAE3148);

  static const darkAccent = Color(0xFFFFBC70);
  static const darkBg = Color(0xFF080F29);
  static const darkCardBg = Color(0xFF141E40);
  static const darkTextPrimary = Color(0xFFFFF3E2);
  static const darkTextSecondary = Color(0xFFBCC3DC);
  static const darkOutline = Color(0xFF344164);
  static const darkDanger = Color(0xFFFF8B9B);

  static Color onAccent(bool isNight) => isNight ? brandNavy : Colors.white;
  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final night = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: brandOrange,
          brightness: brightness,
        ).copyWith(
          primary: night ? darkAccent : lightPrimary,
          onPrimary: onAccent(night),
          secondary: night ? brandGold : brandIndigo,
          onSecondary: night ? brandNavy : Colors.white,
          surface: night ? darkCardBg : lightCardBg,
          onSurface: night ? darkTextPrimary : lightTextPrimary,
          primaryContainer: night
              ? const Color(0xFF4B301D)
              : const Color(0xFFFFE7CD),
          onPrimaryContainer: night ? brandGold : const Color(0xFF6E2910),
          secondaryContainer: night
              ? const Color(0xFF23305C)
              : const Color(0xFFE1E7FA),
          onSecondaryContainer: night ? const Color(0xFFE4EAFE) : brandNavy,
          surfaceContainerLowest: night ? darkBg : lightCardBg,
          surfaceContainerLow: night ? darkCardBg : lightCardBg,
          surfaceContainer: night
              ? const Color(0xFF1A254B)
              : const Color(0xFFFFF1DE),
          surfaceContainerHigh: night
              ? const Color(0xFF202C53)
              : const Color(0xFFF7ECDD),
          surfaceContainerHighest: night
              ? const Color(0xFF27335C)
              : const Color(0xFFEFE5D7),
          outlineVariant: night ? darkOutline : lightOutline,
          onSurfaceVariant: night ? darkTextSecondary : lightTextSecondary,
          outline: night ? darkOutline : lightOutline,
          error: night ? darkDanger : lightDanger,
        );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: night ? darkBg : lightBg,
      appBarTheme: AppBarTheme(
        backgroundColor: night ? darkBg : lightBg,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(color: scheme.surface, elevation: 0),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: .5),
      ),
      fontFamily: 'sans-serif',
    );
  }
}
