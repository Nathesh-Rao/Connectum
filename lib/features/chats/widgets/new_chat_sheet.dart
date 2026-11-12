import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../core/widgets/app_text_field.dart';
import '../new_chat_controller.dart';

class NewChatSheet extends StatelessWidget {
  const NewChatSheet({super.key, required this.controller});

  final NewChatController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: c.queryField,
          hint: 'Search by exact username',
          minHeight: AppSpacing.searchHeight,
          fillColor: AppColors.searchFill,
          borderColor: Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xs)),
          textStyle: AppText.input,
          leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
          onChanged: c.onQueryChanged,
          textInputAction: TextInputAction.search,
        ),
        const SizedBox(height: AppSpacing.sm),
        Obx(() {
          final people = c.people;
          final query = c.query.value.trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.explanation.value != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppHighlightText(
                    c.explanation.value!,
                    values: c.explanationValues,
                  ),
                ),
              for (final p in people)
                AppListRow(
                  title: p.name,
                  subtitle: p.source == 'search' ? '@${p.username}' : null,
                  minHeight: AppSpacing.settingRowHeight,
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.rowChevron,
                  ),
                  onTap: () => c.start(p),
                ),
              if (people.isEmpty && !c.isSearching.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Column(
                    children: [
                      if (!c.isOffline)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppStateImage(
                            kind: query.isEmpty
                                ? AppStateImageKind.emptyChats
                                : AppStateImageKind.noResults,
                            size: AppSpacing.stateImageSmall,
                          ),
                        ),
                      Text(
                        query.isEmpty
                            ? 'People you chat with will show up here.'
                            : c.isOffline
                            ? 'Finding someone new needs a connection.'
                            : 'No one found.',
                        style: AppText.readable,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (c.isSearching.value)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('Searching…', style: AppText.readable),
                ),
              AppListRow(
                title: 'New group',
                subtitle: 'Create a group and add people',
                leading: const Icon(
                  Icons.group_add_outlined,
                  size: 22,
                  color: AppColors.primaryBright,
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.rowChevron,
                ),
                minHeight: AppSpacing.settingRowHeight,
                onTap: c.openNewGroup,
              ),
            ],
          );
        }),
      ],
    );
  }
}
