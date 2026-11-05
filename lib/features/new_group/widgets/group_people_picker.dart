import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../chats/models/chat_person.dart';
import '../new_group_controller.dart';

/// Selected chips with a count, a search field and the people list.
class GroupPeoplePicker extends StatelessWidget {
  const GroupPeoplePicker({super.key, required this.controller});

  final NewGroupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final picked = c.selected.toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                picked.isEmpty
                    ? 'Add people (optional)'
                    : '${picked.length} selected',
                style: AppText.fieldLabel,
              ),
              if (picked.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final p in picked)
                        _SelectedChip(person: p, onRemove: () => c.toggle(p)),
                    ],
                  ),
                ),
              if (c.isOverEncryptionLimit)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'A group of more than 200 people cannot be end-to-end '
                    'encrypted.',
                    style: AppText.readable.copyWith(color: AppColors.error),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: c.queryField,
          hint: 'Search by name or username',
          minHeight: AppSpacing.searchHeight,
          fillColor: AppColors.searchFill,
          borderColor: Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xs)),
          textStyle: AppText.input,
          leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
          onChanged: c.onQueryChanged,
          textInputAction: TextInputAction.search,
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// The scrolling list under [GroupPeoplePicker].
class GroupPeopleList extends StatelessWidget {
  const GroupPeopleList({super.key, required this.controller});

  final NewGroupController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final people = [...c.people, ...c.extras];
      c.selected.length;
      return AppStateView(
        state: c.listState.value,
        onRetry: c.loadPeople,
        emptyTitle: 'No one to add yet',
        emptyMessage: 'People you can add will show up here.',
        errorMessage: 'We could not load the list of people.',
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 200) c.loadMore();
            return false;
          },
          child: ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: people.length + (c.isLoadingMore.value ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= people.length) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Center(
                    child: Text('Loading…', style: AppText.readable),
                  ),
                );
              }
              final p = people[i];
              return _PersonRow(
                person: p,
                isSelected: c.isSelected(p),
                onTap: () => c.toggle(p),
              );
            },
          ),
        ),
      );
    });
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.isSelected,
    required this.onTap,
  });

  final ChatPerson person;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caption = person.detail.isNotEmpty
        ? person.detail
        : '@${person.username}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.settingRowHeight,
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            AppAvatar(name: person.name, size: AppSpacing.avatarSmall),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: AppText.readableStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    caption,
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (person.source != 'connection') ...[
              const AppTag(label: 'Invite'),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              size: 22,
              color: isSelected ? AppColors.accent : AppColors.inputBorder,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.person, required this.onRemove});

  final ChatPerson person;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.only(
          left: AppSpacing.sm,
          right: AppSpacing.xs,
          top: AppSpacing.xxs,
          bottom: AppSpacing.xxs,
        ),
        decoration: const BoxDecoration(
          color: AppColors.accentTint,
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              person.name,
              style: AppText.readable.copyWith(color: AppColors.accentInk),
            ),
            const SizedBox(width: AppSpacing.xxs),
            const Icon(Icons.close, size: 14, color: AppColors.accentInk),
          ],
        ),
      ),
    );
  }
}
