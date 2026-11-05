import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../data/models/group_add.dart';
import '../new_group_controller.dart';

/// What the screen shows once Create is tapped: the work in progress, the
/// "could not confirm" step, or the per-person result.
class GroupProgressView extends StatelessWidget {
  const GroupProgressView({super.key, required this.controller});

  final NewGroupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      switch (c.phase.value) {
        case NewGroupPhase.creating:
          return const _Status(line: 'Creating the group…');
        case NewGroupPhase.adding:
          return _Status(
            line: 'Adding ${c.progress.value} of ${c.total.value}',
            value: c.total.value == 0 ? 0 : c.progress.value / c.total.value,
          );
        case NewGroupPhase.unconfirmed:
          return _Unconfirmed(controller: c);
        case NewGroupPhase.done:
          return _Result(controller: c);
        case NewGroupPhase.editing:
          return const SizedBox.shrink();
      }
    });
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.line, this.value});

  final String line;
  final double? value;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(line, style: AppText.subtitle, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.md),
        if (value != null) AppProgressBar(value: value!),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Please keep this screen open.',
          style: AppText.readable,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _Unconfirmed extends StatelessWidget {
  const _Unconfirmed({required this.controller});

  final NewGroupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final isChecking = c.isChecking.value;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppStateImage(
              kind: AppStateImageKind.error,
              size: AppSpacing.stateImageSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              "We didn't hear back",
              style: AppText.subtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isChecking
                  ? 'Checking your groups to see whether it was created…'
                  : c.unconfirmedText.value ??
                        'Checking your groups to see whether it was created…',
              style: AppText.readable,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton.secondary(
              label: 'Check again',
              isLoading: isChecking,
              onPressed: isChecking ? null : c.checkCreated,
            ),
          ],
        ),
      );
    });
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.controller});

  final NewGroupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListView(
      children: [
        AppHighlightText(
          c.isAddingToExisting ? 'People added' : '"{group}" was created',
          values: {'group': c.groupName},
          style: AppText.subtitle,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(c.summary, style: AppText.readable),
        const SizedBox(height: AppSpacing.md),
        for (final r in c.results) _ResultRow(result: r),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final GroupAddResult result;

  @override
  Widget build(BuildContext context) {
    final (icon, color, line) = switch (result.status) {
      GroupAddStatus.added => (Icons.check_circle, AppColors.yesDot, 'Added'),
      GroupAddStatus.invited => (
        Icons.schedule,
        AppColors.muted,
        'Invited, waiting for them to accept',
      ),
      GroupAddStatus.failed => (
        Icons.error_outline,
        AppColors.error,
        result.reason.isEmpty ? 'Could not be added' : result.reason,
      ),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.settingRowHeight),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          AppAvatar(name: result.person.name, size: AppSpacing.avatarSmall),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.person.name, style: AppText.readableStrong),
                Text(
                  line,
                  style: AppText.caption.copyWith(
                    color: result.status == GroupAddStatus.failed
                        ? AppColors.error
                        : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 20, color: color),
        ],
      ),
    );
  }
}
