import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text.dart';

class AppTheme {
  AppTheme._();

  static final light = ThemeData(
    useMaterial3: true,
    fontFamily: AppText.fontFamily,
    scaffoldBackgroundColor: AppColors.white,
    canvasColor: AppColors.white,
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.white),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.white,
      modalBackgroundColor: AppColors.white,
    ),
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.primaryTint,
      onPrimaryContainer: AppColors.primaryStrong,
      secondary: AppColors.violet,
      onSecondary: AppColors.white,
      secondaryContainer: AppColors.violetTint,
      onSecondaryContainer: AppColors.violetStrong,
      surface: AppColors.white,
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
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.white,
      contentTextStyle: AppText.readable,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: AppColors.line,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? AppColors.primaryBright : null,
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primaryBright,
      thumbColor: AppColors.primaryBright,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primaryBright,
      linearTrackColor: AppColors.primaryTint,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryBright,
      foregroundColor: AppColors.white,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primaryBright,
      selectionHandleColor: AppColors.primaryBright,
      selectionColor: AppColors.primaryBright.withValues(alpha: 0.25),
    ),
  );
}
