import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/models/message.dart';
import '../workspace_controller.dart';

/// The notes I saved, newest first, from the phone (no network needed). A
/// tap shows the note in the thread; the bookmark button removes it from
/// saved.
class WorkspaceSavedSheet extends StatelessWidget {
  const WorkspaceSavedSheet({super.key, required this.controller});

  final WorkspaceController controller;

  static Future<void> show(
    BuildContext context,
    WorkspaceController controller,
  ) => AppBottomSheet.show<void>(
    context,
    title: 'Saved notes',
    child: WorkspaceSavedSheet(controller: controller),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final saved = c.savedNotes();
    if (saved.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          'No saved notes yet. Choose Save on a note to keep it here.',
          style: AppText.readable,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in saved)
          _SavedRow(
            key: ValueKey('saved-${m.msgId}'),
            message: m,
            text: c.noteLine(m),
            onTap: () {
              Navigator.of(context).pop();
              c.openNote(m.msgId);
            },
            onRemove: () {
              Navigator.of(context).pop();
              c.toggleSave(m);
            },
          ),
      ],
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    super.key,
    required this.message,
    required this.text,
    required this.onTap,
    required this.onRemove,
  });

  final Message message;
  final String text;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: AppSpacing.settingRowHeight),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle,
                  ),
                  Text(
                    '${ChatTime.date(message.ts)}  ${ChatTime.time(message.ts, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context))}',
                    style: AppText.rowCaption,
                  ),
                ],
              ),
            ),
          ),
        ),
        AppButton.icon(
          icon: Icons.bookmark_remove_outlined,
          semanticLabel: 'Remove from saved',
          onPressed: onRemove,
        ),
      ],
    ),
  );
}
