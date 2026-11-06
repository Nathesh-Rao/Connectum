import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../enterprises/widgets/enterprise_tile.dart';
import '../enterprise_switcher_controller.dart';
import '../../../core/widgets/app_spinner.dart';

class EnterpriseSwitcherSheet extends StatelessWidget {
  const EnterpriseSwitcherSheet({super.key, required this.controller});

  final EnterpriseSwitcherController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final list = c.enterprises;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('One account. Every enterprise.', style: AppText.body),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < list.length; i++)
            AppListRow(
              leading: EnterpriseTile(
                index: i,
                isCurrent: list[i].enterprise == c.currentOrgId,
              ),
              title: list[i].name,
              subtitle: list[i].isActive
                  ? 'Member · ${list[i].enterprise}'
                  : list[i].status == 'pending'
                  ? 'Waiting for approval · ${list[i].enterprise}'
                  : 'Not approved · ${list[i].enterprise}',
              trailing: c.enteringId.value == list[i].enterprise
                  ? const AppSpinner(size: AppSpinnerSize.sm)
                  : list[i].enterprise == c.currentOrgId
                  ? const EnterpriseCurrentCheck()
                  : list[i].isActive
                  ? const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.rowChevron,
                    )
                  : null,
              onTap: () => c.switchTo(list[i]),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (c.waiting.value > 0)
            _Note(
              '${c.waiting.value} ${c.waiting.value == 1 ? 'message' : 'messages'} waiting to send will go out when you return to {org}.',
              values: {'org': c.currentName},
              color: AppColors.accentInk,
            ),
          if (c.message.value != null)
            _Note(c.message.value!, color: AppColors.error),
          if (c.isOffline) const _Note('Switching needs a connection.'),
          const _Note(
            'Entering an enterprise signs out your other devices that are signed in to it.',
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.primary(
            label: 'Join another enterprise',
            leadingIcon: Icons.add,
            icon: Icons.chevron_right,
            isCompact: true,
            onPressed: c.joinAnother,
          ),
        ],
      );
    });
  }
}

class _Note extends StatelessWidget {
  const _Note(
    this.text, {
    this.color = AppColors.muted,
    this.values = const {},
  });

  final String text;
  final Color color;
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: AppHighlightText(
      text,
      values: values,
      style: AppText.caption.copyWith(color: color),
    ),
  );
}
