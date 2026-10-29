import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import 'debug_e2e_controller.dart';

class DebugE2eView extends GetView<DebugE2eController> {
  const DebugE2eView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Debug: E2E vectors', style: AppText.heading),
          const SizedBox(height: AppSpacing.sm),
          Obx(() {
            final isRunning = c.isRunning.value;
            final isPassed = c.isAllPassed;
            final label = isRunning
                ? 'Running...'
                : c.results.isEmpty
                ? 'No result'
                : isPassed
                ? 'ALL ${c.results.length} PASSED'
                : '${c.failedCount} FAILED of ${c.results.length}';
            return Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isRunning || c.results.isEmpty
                    ? AppColors.noFill
                    : isPassed
                    ? AppColors.yesFill
                    : AppColors.accentTint,
                borderRadius: AppRadius.mdAll,
              ),
              child: Text(
                label,
                style: AppText.subtitle.copyWith(
                  color: isPassed ? AppColors.yesText : AppColors.error,
                ),
              ),
            );
          }),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in c.results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: Text(
                      '${r.isPassed ? 'PASS' : 'FAIL'}  ${r.name}'
                      '${r.detail.isEmpty ? '' : ' (${r.detail})'}',
                      style: AppText.readable.copyWith(
                        color: r.isPassed ? AppColors.yesText : AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => AppButton.secondary(
              label: 'Run again',
              onPressed: c.isRunning.value ? null : c.run,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
