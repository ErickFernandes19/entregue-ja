import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    scaffoldBackgroundColor: AppColors.background,

    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),

    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),

    cardTheme: CardThemeData(
      elevation: 3,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 58),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      labelStyle: const TextStyle(color: AppColors.subtitle),
      hintStyle: const TextStyle(color: AppColors.subtitle),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),

    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppColors.text),
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.subtitle),
      titleLarge: TextStyle(color: AppColors.text),
      titleMedium: TextStyle(color: AppColors.text),
      titleSmall: TextStyle(color: AppColors.text),
    ),

    dividerColor: AppColors.border,
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    scaffoldBackgroundColor: AppColors.darkBackground,

    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      surface: AppColors.darkCard,
    ),

    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),

    cardTheme: CardThemeData(
      elevation: 3,
      color: AppColors.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 58),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkCard,
      labelStyle: const TextStyle(color: AppColors.darkSubtitle),
      hintStyle: const TextStyle(color: AppColors.darkSubtitle),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
      ),
    ),

    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppColors.darkText),
      bodyMedium: TextStyle(color: AppColors.darkText),
      bodySmall: TextStyle(color: AppColors.darkSubtitle),
      titleLarge: TextStyle(color: AppColors.darkText),
      titleMedium: TextStyle(color: AppColors.darkText),
      titleSmall: TextStyle(color: AppColors.darkText),
    ),

    iconTheme: const IconThemeData(color: AppColors.darkText),

    dividerColor: AppColors.darkBorder,

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkCard,
    ),
  );
}
