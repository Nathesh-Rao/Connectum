import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import 'debug_refresh_controller.dart';

/// Debug only: the pull-to-refresh spinner with a slow fake refresh.
class DebugRefreshView extends GetView<DebugRefreshController> {
  const DebugRefreshView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Pull to refresh', style: AppText.display),
                Obx(
                  () => Text(
                    'Refreshes: ${controller.refreshCount.value}. '
                    'Size ${controller.size.value.round()} dp.',
                    style: AppText.body,
                  ),
                ),
                Obx(
                  () => Slider(
                    min: 16,
                    max: 48,
                    value: controller.size.value,
                    onChanged: (v) => controller.size.value = v,
                  ),
                ),
                Obx(
                  () => SegmentedButton<int>(
                    segments: [
                      for (
                        var i = 0;
                        i < DebugRefreshController.colors.length;
                        i++
                      )
                        ButtonSegment(
                          value: i,
                          label: Text(DebugRefreshController.colorNames[i]),
                        ),
                    ],
                    selected: {controller.colorIndex.value},
                    onSelectionChanged: (s) =>
                        controller.colorIndex.value = s.first,
                  ),
                ),
                Obx(
                  () => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fails after 1 s (2 s otherwise)'),
                    value: controller.isFailing.value,
                    onChanged: (v) => controller.isFailing.value = v,
                  ),
                ),
                Obx(
                  () => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reduced motion preview'),
                    value: controller.isReducedMotion.value,
                    onChanged: (v) => controller.isReducedMotion.value = v,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(
              () => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: controller.isReducedMotion.value),
                child: AppRefresh(
                  onRefresh: controller.fakeRefresh,
                  spinnerSize: controller.size.value,
                  spinnerColor: DebugRefreshController
                      .colors[controller.colorIndex.value],
                  slivers: [
                    SliverList.builder(
                      itemCount: 30,
                      itemBuilder: (context, i) =>
                          ListTile(title: Text('Row $i', style: AppText.body)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
