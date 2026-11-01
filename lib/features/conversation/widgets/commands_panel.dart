import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../data/models/hash_command.dart';
import '../models/command_prompt.dart';

/// The "#" commands sheet, drawn above the composer so the text keeps
/// focus and the list narrows as the name is typed. Choosing a row only puts
/// `#name ` into the composer.
class CommandsPanel extends StatelessWidget {
  const CommandsPanel({
    super.key,
    required this.prompt,
    required this.onPick,
    required this.isOnline,
  });

  final CommandPrompt prompt;
  final ValueChanged<HashCommand> onPick;
  final bool Function() isOnline;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AppDurations.fast,
    curve: AppCurves.out,
    alignment: Alignment.bottomCenter,
    child: Obx(() {
      if (prompt.query.value == null) {
        return const SizedBox(width: double.infinity);
      }
      final rows = prompt.matches;
      final hasCatalog = prompt.hasCatalog;
      final isLoading = prompt.isLoading;
      final empty = !hasCatalog
          ? (isLoading
                ? 'Loading commands…'
                : isOnline()
                ? "Commands aren't available right now."
                : 'Commands need a connection the first time.')
          : 'No matching command';
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.3,
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sheetPaddingX,
          AppSpacing.sm,
          AppSpacing.sheetPaddingX,
          0,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadius.sheetTop,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text('Commands', style: AppText.subtitle),
            ),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(empty, style: AppText.readable),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.manual,
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final c = rows[i];
                        return AppListRow(
                          key: ValueKey(c.name),
                          title: c.summary.isEmpty
                              ? '# ${c.name}'
                              : '# ${c.name} — ${c.summary}',
                          minHeight: AppSpacing.minTapTarget,
                          titleStyle: c.isAvailable
                              ? AppText.rowTitle
                              : AppText.rowTitle.copyWith(
                                  color: AppColors.muted,
                                ),
                          onTap: () => onPick(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }),
  );
}
