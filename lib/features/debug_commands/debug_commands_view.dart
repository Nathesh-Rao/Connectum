import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import 'debug_commands_controller.dart';

class DebugCommandsView extends GetView<DebugCommandsController> {
  const DebugCommandsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          const Text('# commands (fixture)', style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'The catalogue of the doc and fake answers; nothing reaches a server. '
            'Type a # line to see the menu, the argument choices and the checks.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: c.text,
            focusNode: c.focus,
            hint: 'Type #dm ana hello',
            onChanged: c.onChanged,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Check this line', onPressed: c.validate),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Stale reply demo',
            onPressed: c.staleDemo,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'unknown_command error',
            onPressed: c.unknown,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'usage error', onPressed: c.usage),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final l in c.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: Text(l, style: AppText.caption),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
