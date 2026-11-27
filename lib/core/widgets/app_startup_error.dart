import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'app_button.dart';

/// Shown when something that must work before the app can open failed.
class AppStartupError extends StatelessWidget {
  const AppStartupError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: AppColors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.page),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Couldn't start the app",
                    style: AppText.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Please try again.',
                    style: AppText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton.primary(label: 'Try again', onPressed: onRetry),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
