import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/selection/selection_rules.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import '../conversation_controller.dart';
import '../conversation_tour_demo.dart';
import 'emoji_picker_sheet.dart';
import 'forward_sheet.dart';
import 'form_message_sheet.dart';

/// The selection bar of a conversation: what the selected messages allow,
/// built from [SelectionRules] and the controller's conditions.
class ConversationSelectionBar extends StatelessWidget {
  const ConversationSelectionBar({
    super.key,
    required this.controller,
    this.sample,
  });

  final ConversationController controller;

  /// The chat tour's sample thread: the bar then shows what the sample
  /// message allows, and every item does nothing.
  final ConversationTourDemo? sample;

  @override
  Widget build(BuildContext context) => Obx(() {
    final c = controller;
    final demo = sample;
    final list = demo == null ? c.selectedMessages : demo.selectedMessages;
    final actions = SelectionRules.available([
      for (final m in list)
        demo == null ? c.targetOf(m) : ConversationTourDemo.targetOf(demo.caps),
    ], isEditIcon: true);
    final items = [
      for (final a in actions) _item(context, a, list),
    ].whereType<SelectionBarItem>().toList();
    return SelectionAppBar(
      count: list.length,
      isEditIcon: true,
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
            c.retry(first);
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
      case SelectionAction.delete:
        return SelectionBarItem(
          action: action,
          icon: Icons.delete_outline,
          label: 'Delete',
          onTap: () => _confirmDelete(context, list),
        );
      case SelectionAction.forward:
        return SelectionBarItem(
          action: action,
          icon: Icons.shortcut,
          label: 'Forward',
          onTap: () {
            c.selection.clear();
            ForwardSheet.showMany(context, c, list);
          },
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
      case SelectionAction.formMenu:
        return SelectionBarItem(
          action: action,
          icon: Icons.assignment_outlined,
          label: 'Form actions',
          onTap: () {
            c.selection.clear();
            FormMessageSheet.show(context, c, first);
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
      case SelectionAction.star:
      case SelectionAction.pin:
        // Chats have no save or pin of a message: never offered here.
        return null;
    }
  }

  Future<void> _confirmDelete(BuildContext context, List<Message> list) async {
    final c = controller;
    final isOne = list.length == 1;
    final isDone = await DeleteConfirmSheet.show(
      context,
      title: isOne ? 'Delete message?' : 'Delete ${list.length} messages?',
      text: isOne
          ? 'This message is removed for everyone in the conversation.'
          : 'These messages are removed for everyone in the conversation.',
      onDelete: () => c.deleteMany(list),
    );
    if (isDone ?? false) c.selection.clear();
  }
}

/// The reaction bar over the thread: only for one selected message that takes
/// reactions (never in teams, never for two messages).
class ConversationReactionOverlay extends StatelessWidget {
  const ConversationReactionOverlay({
    super.key,
    required this.controller,
    this.barKey,
    this.sample,
  });

  final ConversationController controller;

  /// The tour's target on the bar.
  final GlobalKey? barKey;

  /// The chat tour's sample thread: the bar is drawn for the sample message
  /// and picks nothing.
  final ConversationTourDemo? sample;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final demo = sample;
    if (demo != null) {
      return IgnorePointer(
        child: SelectionBarOverlay(
          selection: demo.selection,
          scroll: c.scroll,
          isShown: () =>
              demo.selection.isSingle &&
              ConversationTourDemo.targetOf(demo.caps).canReact,
          barWidth: SelectionReactionBar.idealWidth(Reaction.quick.length),
          bar: (width) => KeyedSubtree(
            key: barKey,
            child: SelectionReactionBar(
              emojis: Reaction.quick,
              mine: const {},
              onPick: (_) {},
              onMore: () {},
            ),
          ),
        ),
      );
    }
    return SelectionBarOverlay(
      selection: c.selection,
      scroll: c.scroll,
      isShown: () {
        final list = c.selectedMessages;
        return SelectionRules.showsReactions([
          for (final m in list) c.targetOf(m),
        ], isSupported: list.length == c.selection.ids.length);
      },
      barWidth: SelectionReactionBar.idealWidth(Reaction.quick.length),
      bar: (width) {
        final m = c.selectedMessages.firstOrNull;
        final mine = m == null
            ? <String>{}
            : {
                for (final r in c.reactionsOf(m))
                  if (r.isMine) r.emoji,
              };
        return KeyedSubtree(
          key: barKey,
          child: SelectionReactionBar(
            emojis: Reaction.quick,
            mine: mine,
            onPick: c.reactSelected,
            onMore: () async {
              final id = m;
              final emoji = await EmojiPickerSheet.show(context, mine: mine);
              if (emoji != null && id != null) {
                c.selection.clear();
                await c.toggleReaction(id, emoji);
              }
            },
          ),
        );
      },
    );
  }
}
