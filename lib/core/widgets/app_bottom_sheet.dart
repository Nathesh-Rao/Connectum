import 'dart:math' as math;

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
    Widget? titleWidget,
    bool hasClose = true,
    bool hasHeader = true,
    VoidCallback? onDispose,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
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
      builder: (context) => _SheetLifetime(
        onDispose: onDispose,
        child: RepaintBoundary(
          child: _SheetBody(
            title: title,
            titleWidget: titleWidget,
            hasClose: hasClose,
            hasHeader: hasHeader,
            child: child,
          ),
        ),
      ),
    );
  }

  /// A fixed-height sheet with no header: handle, then [child], which gets
  /// the rest of the height. Nothing in it scrolls, so a downward drag
  /// anywhere on the sheet closes it.
  static Future<T?> showFixed<T>(
    BuildContext context, {
    required Widget child,
  }) {
    final media = MediaQuery.of(context);
    final height = math.min(
      media.size.height * AppSpacing.fixedSheetFraction,
      media.size.height - media.padding.top,
    );
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.sheetBackdrop,
      elevation: 0,
      sheetAnimationStyle: AnimationStyle(
        duration: AppDurations.slow,
        reverseDuration: AppDurations.base,
        curve: AppCurves.sheet,
        reverseCurve: AppCurves.out,
      ),
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(minScaleFactor: 1, maxScaleFactor: 1.3),
        ),
        child: _FixedSheetBody(height: height, child: child),
      ),
    );
  }
}

/// Runs [onDispose] when the sheet's widgets are removed, after the closing
/// animation. The route's future completes when the sheet starts to close,
/// while the fields inside still rebuild, so a controller they use must be
/// disposed here, not in `whenComplete`.
class _SheetLifetime extends StatefulWidget {
  const _SheetLifetime({required this.child, this.onDispose});

  final VoidCallback? onDispose;
  final Widget child;

  @override
  State<_SheetLifetime> createState() => _SheetLifetimeState();
}

class _SheetLifetimeState extends State<_SheetLifetime> {
  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FixedSheetBody extends StatelessWidget {
  const _FixedSheetBody({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.sheetTop,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sheetPaddingX,
            AppSpacing.sheetPaddingTop,
            AppSpacing.sheetPaddingX,
            AppSpacing.sheetPaddingBottom + bottomInset,
          ),
          child: Column(
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
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.child,
    this.titleWidget,
    this.hasClose = true,
    this.hasHeader = true,
  });

  final String title;
  final Widget? titleWidget;
  final bool hasClose;

  /// False: the handle, then the child; the child brings its own title.
  final bool hasHeader;
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
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sheetPaddingX,
              AppSpacing.sheetPaddingTop,
              AppSpacing.sheetPaddingX,
              AppSpacing.sheetPaddingBottom +
                  MediaQuery.paddingOf(context).bottom,
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
                if (hasHeader) ...[
                  Row(
                    children: [
                      Expanded(
                        child: titleWidget ?? Text(title, style: AppText.title),
                      ),
                      if (hasClose)
                        AppButton.icon(
                          icon: Icons.close,
                          semanticLabel: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
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
