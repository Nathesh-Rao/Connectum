import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/selection/selection_rules.dart';
import '../../../core/widgets/message_selection/delete_confirm_sheet.dart';
import '../../../core/widgets/message_selection/selection_app_bar.dart';
import '../../../data/models/message.dart';
import '../workspace_controller.dart';
import '../workspace_tour_demo.dart';

/// The selection bar of My Work Space: reply, star, delete, and in the menu
/// copy, pin and edit. A note that was not sent keeps retry and remove. There
/// is no reaction bar: the server refuses `/react` for notes.
class WorkspaceSelectionBar extends StatelessWidget {
  const WorkspaceSelectionBar({
    super.key,
    required this.controller,
    this.sample,
  });

  final WorkspaceController controller;

  /// The tour's sample note: the bar then shows what the sample allows, and
  /// every item does nothing.
  final WorkspaceTourDemo? sample;

  @override
  Widget build(BuildContext context) => Obx(() {
    final c = controller;
    final demo = sample;
    final list = demo == null ? c.selectedNotes : demo.selectedNotes;
    final actions = SelectionRules.available([
      for (final m in list)
        demo == null ? c.targetOf(m) : WorkspaceTourDemo.target,
    ]);
    final items = [
      for (final a in actions) _item(context, a, list),
    ].whereType<SelectionBarItem>().toList();
    return SelectionAppBar(
      count: list.length,
      onExit: demo == null ? c.selection.clear : demo.clearSelection,
      items: demo == null
          ? items
          : [
              for (final i in items)
                SelectionBarItem(
                  action: i.action,
                  icon: i.icon,
                  label: i.label,
                  onTap: () {},
                ),
            ],
    );
  });

  SelectionBarItem? _item(
    BuildContext context,
    SelectionAction action,
    List<Message> list,
  ) {
    final c = controller;
    final first = list.first;
    switch (action) {
      case SelectionAction.retry:
        return SelectionBarItem(
          action: action,
          icon: Icons.refresh,
          label: 'Retry',
          onTap: () {
            c.selection.clear();
            c.retryNote(first);
          },
        );
      case SelectionAction.reply:
        return SelectionBarItem(
          action: action,
          icon: Icons.reply,
          label: 'Reply',
          onTap: () {
            c.selection.clear();
            c.startReply(first);
          },
        );
      case SelectionAction.star:
        final isAllSaved = list.every(c.isSaved);
        return SelectionBarItem(
          action: action,
          icon: isAllSaved ? Icons.bookmark : Icons.bookmark_border,
          label: isAllSaved ? 'Remove from saved' : 'Save',
          onTap: () {
            c.selection.clear();
            c.toggleSaveMany(list);
          },
        );
      case SelectionAction.delete:
        final isUnsent = list.every(c.isUnsent);
        return SelectionBarItem(
          action: action,
          icon: Icons.delete_outline,
          label: isUnsent ? 'Remove' : 'Delete',
          onTap: () => _delete(context, list, isUnsent: isUnsent),
        );
      case SelectionAction.copy:
        return SelectionBarItem(
          action: action,
          icon: Icons.copy,
          label: 'Copy',
          onTap: () {
            c.copyMany(list);
            c.selection.clear();
          },
        );
      case SelectionAction.pin:
        final isPinned = c.isPinned(first);
        return SelectionBarItem(
          action: action,
          icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          label: isPinned ? 'Unpin' : 'Pin',
          onTap: () {
            c.selection.clear();
            c.togglePin(first);
          },
        );
      case SelectionAction.edit:
        return SelectionBarItem(
          action: action,
          icon: Icons.edit_outlined,
          label: 'Edit',
          onTap: () {
            c.selection.clear();
            c.startEdit(first);
          },
        );
      case SelectionAction.forward:
      case SelectionAction.formMenu:
        return null;
    }
  }

  Future<void> _delete(
    BuildContext context,
    List<Message> list, {
    required bool isUnsent,
  }) async {
    final c = controller;
    if (isUnsent) {
      c.selection.clear();
      await c.deleteMany(list);
      return;
    }
    final isOne = list.length == 1;
    final isDone = await DeleteConfirmSheet.show(
      context,
      title: isOne ? 'Delete this note?' : 'Delete ${list.length} notes?',
      text: 'It is removed from My Work Space on all your devices.',
      onDelete: () async {
        await c.deleteMany(list);
        return null;
      },
    );
    if (isDone ?? false) c.selection.clear();
  }
}
