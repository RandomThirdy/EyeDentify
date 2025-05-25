import 'package:flutter/material.dart';

class AppTheme {
  // Beige-based color palette
  static const Color primaryBeige = Color(0xFFE8D5C4);
  static const Color secondaryBeige = Color(0xFFF5EBE0);
  static const Color accentBeige = Color(0xFFD4B996);
  static const Color darkBeige = Color(0xFFC3A78E);
  static const Color lightBeige = Color(0xFFFDF6F0);
  static const Color textBrown = Color(0xFF6B4F4F);
  static const Color mutedBrown = Color(0xFF8B7355);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: primaryBeige,
      secondary: secondaryBeige,
      tertiary: accentBeige,
      surface: lightBeige,
      background: lightBeige,
      onPrimary: textBrown,
      onSecondary: textBrown,
      onTertiary: textBrown,
      onSurface: textBrown,
      onBackground: textBrown,
    ),
    scaffoldBackgroundColor: lightBeige,
      cardTheme: CardThemeData(
      color: secondaryBeige,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),

    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: textBrown,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: TextStyle(
        color: textBrown,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: textBrown,
        fontSize: 16,
      ),
      bodyMedium: TextStyle(
        color: mutedBrown,
        fontSize: 14,
      ),
    ),
    iconTheme: const IconThemeData(
      color: mutedBrown,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBeige,
        foregroundColor: textBrown,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}