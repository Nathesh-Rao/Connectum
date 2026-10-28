import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text.dart';

class AppTheme {
  AppTheme._();

  static final light = ThemeData(
    useMaterial3: true,
    fontFamily: AppText.fontFamily,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: AppColors.background,
      secondary: AppColors.accentTint,
      onSecondary: AppColors.accentInk,
      surface: AppColors.background,
      onSurface: AppColors.ink,
      error: AppColors.error,
      outline: AppColors.line,
    ),
    textTheme: const TextTheme(
      displayLarge: AppText.display,
      headlineMedium: AppText.heading,
      titleLarge: AppText.title,
      titleMedium: AppText.subtitle,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.readable,
      labelLarge: AppText.button,
      labelSmall: AppText.caption,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: AppColors.line,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionHandleColor: AppColors.accent,
    ),
  );
}
