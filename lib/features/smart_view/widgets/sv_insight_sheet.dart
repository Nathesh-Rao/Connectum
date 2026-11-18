import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';

/// The shell of the KPI and Charts sheets: a draggable sheet with a grab
/// handle, a title with a tinted icon and a close button; [body] scrolls.
class SvInsightSheet {
  SvInsightSheet._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required IconData icon,
    required AppTone tone,
    required Widget body,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.sheetBackdrop,
      elevation: 0,
      sheetAnimationStyle: AnimationStyle(
        duration: AppDurations.slow,
        reverseDuration: AppDurations.base,
        curve: AppCurves.sheet,
        reverseCurve: AppCurves.out,
      ),
      builder: (sheet) => SvInsightSheetFrame(
        title: title,
        icon: icon,
        tone: tone,
        onClose: () => Navigator.of(sheet).pop(),
        body: body,
      ),
    );
  }
}

class SvInsightSheetFrame extends StatelessWidget {
  const SvInsightSheetFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.tone,
    required this.onClose,
    required this.body,
  });

  final String title;
  final IconData icon;
  final AppTone tone;
  final VoidCallback onClose;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      snap: true,
      builder: (context, scroll) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.sheetTop,
        ),
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sheetPaddingX,
                  AppSpacing.sheetPaddingTop,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        key: const ValueKey('sv-insight-handle'),
                        width: AppSpacing.handleWidth,
                        height: AppSpacing.handleHeight,
                        decoration: const BoxDecoration(
                          color: AppColors.sheetHandle,
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Container(
                          width: AppSv.sheetIconCircle,
                          height: AppSv.sheetIconCircle,
                          decoration: BoxDecoration(
                            color: tone.solid,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: AppSpacing.popupMenuIcon,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(title, style: AppText.subtitle)),
                        IconButton(
                          tooltip: 'Close',
                          constraints: const BoxConstraints.tightFor(
                            width: AppSpacing.badgedIconHit,
                            height: AppSpacing.badgedIconHit,
                          ),
                          icon: const Icon(
                            Icons.close,
                            size: AppSpacing.popupMenuIcon,
                            color: AppColors.muted,
                          ),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.sheetPaddingX,
                0,
                AppSpacing.sheetPaddingX,
                AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverToBoxAdapter(child: body),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Based on N of M records", or "Based on N loaded records" while more
/// pages are still to come.
class SvInsightNote extends StatelessWidget {
  const SvInsightNote({
    super.key,
    required this.shown,
    required this.loaded,
    required this.hasMore,
  });

  final int shown;
  final int loaded;
  final bool hasMore;

  static String textOf(int shown, int loaded, bool hasMore) {
    if (hasMore) return 'Based on $shown loaded records';
    if (shown == loaded) {
      return 'Based on $shown record${shown == 1 ? '' : 's'}';
    }
    return 'Based on $shown of $loaded records';
  }

  @override
  Widget build(BuildContext context) {
    return Text(textOf(shown, loaded, hasMore), style: AppText.supporting);
  }
}

/// A calm block for "nothing to show".
class SvInsightEmpty extends StatelessWidget {
  const SvInsightEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Container(
            width: AppSv.emptyCircle,
            height: AppSv.emptyCircle,
            decoration: const BoxDecoration(
              color: AppColors.violetTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: AppColors.violetStrong),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xxs),
          Text(caption, style: AppText.supporting, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
