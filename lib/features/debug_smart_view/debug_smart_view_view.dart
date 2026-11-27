import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_smart_view.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'debug_smart_view_controller.dart';

class DebugSmartViewView extends GetView<DebugSmartViewController> {
  const DebugSmartViewView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Smart View (debug)', style: AppText.heading),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Sample data answers every call; nothing is sent. Sample user: '
            'ana. The Leave request has a hidden field '
            '(${SeedSmartView.hiddenValue}): it must never show.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sample data, no server', style: AppText.body),
              value: c.isSample.value,
              onChanged: c.isLoading.value ? null : c.toggleSample,
            ),
          ),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Events carry data.record',
                style: AppText.body,
              ),
              subtitle: const Text(
                'On: a server with #822 (patch in place, no command). '
                'Off: a release (one debounced read of the record).',
                style: AppText.caption,
              ),
              value: c.isRecordMode.value,
              onChanged: c.setRecordMode,
            ),
          ),
          for (final s in const [
            ('Leave request (120 records)', 'leave'),
            ('Expense claim (empty)', 'expense'),
            ('Ticket (not_found)', 'help_ticket'),
            ('Work order (fails once)', 'help_task'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: AppButton.secondary(
                label: s.$1,
                onPressed: () => c.open(s.$2),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          const Text('Live', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppButton.secondary(
              label: 'Change a status now',
              onPressed: c.changeNow,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppButton.secondary(
              label: 'Add a record now',
              onPressed: c.addNow,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppButton.secondary(
              label: 'Restart the 10 s / 20 s timers',
              onPressed: c.restartTimers,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: AppButton.secondary(
              label: 'Which live mode was detected?',
              onPressed: c.showMode,
            ),
          ),
          Obx(() {
            final mode = c.liveMode.value;
            return mode == null
                ? const SizedBox.shrink()
                : Text('Live mode: $mode', style: AppText.readable);
          }),
        ],
      ),
    );
  }
}
