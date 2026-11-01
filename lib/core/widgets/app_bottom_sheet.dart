import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_button.dart';

class AppBottomSheet {
  AppBottomSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      barrierColor: AppColors.sheetBackdrop,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      sheetAnimationStyle: AnimationStyle(
        duration: AppDurations.slow,
        reverseDuration: AppDurations.base,
        curve: AppCurves.sheet,
        reverseCurve: AppCurves.out,
      ),
      builder: (context) => RepaintBoundary(
        child: _SheetBody(title: title, child: child),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset =
        MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) => AppSheetScope(
        maxBodyHeight:
            constraints.maxHeight -
            AppSpacing.sheetPaddingTop -
            AppSpacing.handleHeight -
            AppSpacing.lg -
            AppSpacing.minTapTarget -
            AppSpacing.sm -
            AppSpacing.sheetPaddingBottom -
            bottomInset,
        child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.sheetPaddingX,
          AppSpacing.sheetPaddingTop,
          AppSpacing.sheetPaddingX,
          AppSpacing.sheetPaddingBottom + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: AppSpacing.handleWidth,
                height: AppSpacing.handleHeight,
                decoration: const BoxDecoration(
                  color: AppColors.sheetHandle,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: Text(title, style: AppText.title)),
                AppButton.icon(
                  icon: Icons.close,
                  semanticLabel: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
        ),
      ),
    );
  }
}

/// The most height the sheet's body can use, for a body that wants to be tall.
class AppSheetScope extends InheritedWidget {
  const AppSheetScope({
    super.key,
    required this.maxBodyHeight,
    required super.child,
  });

  final double maxBodyHeight;

  static double? maybeMaxBodyHeight(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppSheetScope>()
      ?.maxBodyHeight;

  @override
  bool updateShouldNotify(AppSheetScope oldWidget) =>
      maxBodyHeight != oldWidget.maxBodyHeight;
}
