import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import 'debug_notifications_controller.dart';

class DebugNotificationsView extends GetView<DebugNotificationsController> {
  const DebugNotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget gap() => const SizedBox(height: AppSpacing.xs);
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          const Text('Notification test hooks', style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Events go straight into the feed, as if the server sent them. '
            'Turn on "Act as background" to see system notifications.',
            style: AppText.readable,
          ),
          Row(
            children: [
              const Expanded(
                child: Text('Act as background', style: AppText.body),
              ),
              Obx(
                () => Switch(
                  value: c.isBackground.value,
                  activeThumbColor: AppColors.accent,
                  onChanged: c.setBackground,
                ),
              ),
            ],
          ),
          AppButton.secondary(
            label: 'Plain message',
            onPressed: c.plainMessage,
          ),
          gap(),
          AppButton.secondary(label: 'Mention', onPressed: c.mention),
          gap(),
          AppButton.secondary(
            label: 'Group message (low)',
            onPressed: c.groupMessage,
          ),
          gap(),
          AppButton.secondary(label: 'Approval', onPressed: c.approval),
          gap(),
          AppButton.secondary(label: 'Task', onPressed: c.task),
          gap(),
          AppButton.secondary(label: 'E2E envelope', onPressed: c.e2eEnvelope),
          gap(),
          AppButton.secondary(
            label: 'Coalesced (tap three times)',
            onPressed: c.coalesced,
          ),
          gap(),
          AppButton.secondary(label: 'Read last', onPressed: c.readLast),
          gap(),
          AppButton.secondary(label: 'Resolve last', onPressed: c.resolveLast),
          gap(),
          AppButton.secondary(label: 'Remove last', onPressed: c.removeLast),
          gap(),
          AppButton.primary(
            label: 'Fire a local notification',
            onPressed: c.fireLocal,
          ),
        ],
      ),
    );
  }
}
