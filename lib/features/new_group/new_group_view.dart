import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import '../../data/models/group_add.dart';
import '../../data/repositories/group_repository.dart';
import 'new_group_controller.dart';
import 'widgets/group_people_picker.dart';
import 'widgets/group_progress_view.dart';

class NewGroupView extends GetView<NewGroupController> {
  const NewGroupView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => PopScope(
        canPop: !c.isBusy,
        child: AppScaffold(
          isScrollable: false,
          padding: EdgeInsets.zero,
          bottomBar: _BottomBar(controller: c),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    AppButton.icon(
                      icon: Icons.arrow_back,
                      semanticLabel: 'Back',
                      onPressed: c.isBusy ? null : Get.back,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        c.isAddingToExisting ? 'Add people' : 'Create group',
                        style: AppText.title,
                      ),
                    ),
                  ],
                ),
              ),
              const AppOfflineBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.page,
                  ),
                  child: c.phase.value == NewGroupPhase.editing
                      ? _Editor(controller: c)
                      : GroupProgressView(controller: c),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.controller});

  final NewGroupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (SeedUi.isActive) _SeedChips(controller: c),
        if (!c.isAddingToExisting) ...[
          Obx(() {
            final problem = c.nameProblem;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  controller: c.nameField,
                  label: 'Group name',
                  hint: 'For example, Design team',
                  maxLength: GroupRepository.maxNameLength,
                  errorText: problem,
                  onChanged: c.onNameChanged,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(
                      RegExp(r'[\u0000-\u001F\u007F-\u009F]'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        problem ??
                            'Spaces are fine. You are added as the owner.',
                        style: AppText.caption.copyWith(
                          color: problem == null
                              ? AppColors.muted
                              : AppColors.error,
                        ),
                      ),
                    ),
                    Text(
                      '${c.name.value.length}/${GroupRepository.maxNameLength}',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.md),
        ],
        GroupPeoplePicker(controller: c),
        Expanded(child: GroupPeopleList(controller: c)),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller});

  final NewGroupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Obx(() {
        switch (c.phase.value) {
          case NewGroupPhase.editing:
            final count = c.selected.length;
            return AppButton.primary(
              label: c.isAddingToExisting
                  ? (count == 0 ? 'Add' : 'Add $count')
                  : 'Create group',
              onPressed: c.canSubmit ? c.submit : null,
            );
          case NewGroupPhase.done:
            final failed = c.count(GroupAddStatus.failed);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (c.notice.value != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      c.notice.value!,
                      style: AppText.readable.copyWith(color: AppColors.error),
                    ),
                  ),
                if (failed > 0) ...[
                  AppButton.secondary(
                    label: 'Retry the $failed that failed',
                    onPressed: c.retryFailed,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                AppButton.primary(
                  label: c.isAddingToExisting ? 'Done' : 'Open group',
                  onPressed: c.openGroup,
                ),
              ],
            );
          default:
            return const SizedBox.shrink();
        }
      }),
    );
  }
}

class _SeedChips extends StatelessWidget {
  const _SeedChips({required this.controller});

  final NewGroupController controller;

  static const _states = [
    ('clean', 'Clean'),
    ('name', 'Name conflict'),
    ('prefix', 'Prefix conflict'),
    ('partial', 'Partial failure'),
    ('invite', 'Invite pending'),
    ('offline', 'Offline'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Wrap(
      spacing: AppSpacing.xxs,
      children: [
        for (final (id, label) in _states)
          ActionChip(
            label: Text(label, style: AppText.caption),
            onPressed: () => controller.applySeed(id),
          ),
      ],
    ),
  );
}
