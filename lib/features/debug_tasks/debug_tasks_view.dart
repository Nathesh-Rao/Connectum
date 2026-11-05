import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import 'debug_tasks_controller.dart';

class DebugTasksView extends GetView<DebugTasksController> {
  const DebugTasksView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Tasks and approvals (debug)', style: AppText.heading),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sample data, no server', style: AppText.body),
              value: c.isSample.value,
              onChanged: c.toggleSample,
            ),
          ),
          _Gap(
            AppButton.secondary(label: 'Open Tasks', onPressed: c.openTasks),
          ),
          _Gap(
            AppButton.secondary(
              label: 'Open Approvals',
              onPressed: c.openApprovals,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Inject an event', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          _Gap(
            AppButton.secondary(
              label: 'task_assigned',
              onPressed: c.taskAssigned,
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'task_updated',
              onPressed: c.taskUpdated,
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'request_created',
              onPressed: c.requestCreated,
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'request_resolved',
              onPressed: c.requestResolved,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => Text(
              c.nextFailure.value == null
                  ? 'Make the next call fail'
                  : 'Next call fails: ${c.nextFailure.value}',
              style: AppText.subtitle,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final code in DebugTasksController.failures.keys)
            _Gap(
              AppButton.secondary(
                label: code,
                onPressed: () => c.failNext(code),
              ),
            ),
          AppButton.text(label: 'Clear', onPressed: c.clearFailure),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: child,
  );
}
