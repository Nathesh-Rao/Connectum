import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../smart_view_controller.dart';

/// Search or filters leave no record: a calm line and a way back. Not the
/// empty state of a structure that has no records.
class SvNoMatch extends StatelessWidget {
  const SvNoMatch({super.key, required this.controller});

  final SmartViewController controller;

  static const title = 'No records match';
  static const clearLabel = 'Clear filters';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(title, style: AppText.subtitle),
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              'Try a different word or take a filter off.',
              style: AppText.supporting,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: 180,
              child: AppButton.secondary(
                label: clearLabel,
                onPressed: controller.clearFilters,
              ),
            ),
            Obx(
              () => controller.hasMorePages
                  ? SvLoadNote(controller: controller)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

/// The footer note while a search or filter runs over part of the records:
/// the result is only what has loaded so far.
class SvLoadNote extends StatelessWidget {
  const SvLoadNote({super.key, required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final t = c.table.value;
      if (t == null || !c.query.value.isFiltering || !c.hasMorePages) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Showing results from ${t.rows.length} loaded records — '
                'load more to include the rest',
                style: AppText.caption,
              ),
            ),
            AppButton.text(
              label: 'Load more',
              tone: AppTextButtonTone.accent,
              isLoading: t.isPaging.value,
              onPressed: c.loadMore,
            ),
          ],
        ),
      );
    });
  }
}
