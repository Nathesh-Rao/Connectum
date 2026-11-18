import 'package:flutter/material.dart';

import '../../../data/models/record_state.dart';

/// One row of a card's menu.
class CardMenuItem {
  const CardMenuItem(
    this.id,
    this.label,
    this.icon, {
    this.why = '',
    this.isEnabled = true,
    this.isDanger = false,
    this.isSoon = false,
    this.hasDividerBefore = false,
  });

  final String id;
  final String label;
  final IconData icon;

  /// The server's reason a record action is off, shown under the label.
  final String why;
  final bool isEnabled;
  final bool isDanger;

  /// Offered by the web, not built here yet: shows the "coming soon" notice.
  final bool isSoon;
  final bool hasDividerBefore;

  /// The id of a record action row (`send`, `status`).
  static const actionPrefix = 'act-';
  static const reply = 'reply';
  static const copy = 'copy';
  static const save = 'save';
  static const pin = 'pin';
  static const unread = 'unread';
  static const edit = 'edit';
  static const history = 'history';
  static const delete = 'delete';

  bool get isRecordAction => id.startsWith(actionPrefix);
  String get recordActionId => id.substring(actionPrefix.length);
}

/// What the menu of a form or record card offers, in the web's order
/// (`MessageList.jsx` `menuItems`): Reply, Copy (no Forward: a form or record
/// card is never forwarded); Save, Pin, Mark as
/// unread; the record's own actions from `record.actions` (Send, Update
/// status, each with the server's `why` when off); then Edit or Fix and send
/// again, History and Delete, which the web draws as buttons on the card. The
/// server decides each action again when it is saved; nothing here is a
/// permission.
class CardMenu {
  CardMenu._();

  static List<CardMenuItem> build({
    bool canReply = false,
    bool canCopy = false,
    bool isMarkable = false,
    bool isPinnable = false,
    bool isMine = false,
    RecordState? record,
    bool canEdit = false,
    bool isFix = false,
    bool canOpenHistory = false,
    bool canDelete = false,
  }) {
    final items = <CardMenuItem>[
      if (canReply)
        const CardMenuItem(CardMenuItem.reply, 'Reply', Icons.reply),
      if (canCopy) const CardMenuItem(CardMenuItem.copy, 'Copy', Icons.copy),
    ];
    if (isMarkable) {
      items.add(
        const CardMenuItem(
          CardMenuItem.save,
          'Save this message',
          Icons.bookmark_border,
          isSoon: true,
          hasDividerBefore: true,
        ),
      );
      if (isPinnable) {
        items.add(
          const CardMenuItem(
            CardMenuItem.pin,
            'Pin for everyone',
            Icons.push_pin_outlined,
            isSoon: true,
          ),
        );
      }
      if (!isMine) {
        items.add(
          const CardMenuItem(
            CardMenuItem.unread,
            'Mark as unread',
            Icons.mark_chat_unread_outlined,
            isSoon: true,
          ),
        );
      }
    }
    final actions = record?.items ?? const <RecordActionItem>[];
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      items.add(
        CardMenuItem(
          '${CardMenuItem.actionPrefix}${a.id}',
          a.label,
          a.id == RecordActionItem.send ? Icons.send_outlined : Icons.bolt,
          why: a.isEnabled ? '' : a.why,
          isEnabled: a.isEnabled,
          hasDividerBefore: i == 0,
        ),
      );
    }
    if (canEdit) {
      items.add(
        CardMenuItem(
          CardMenuItem.edit,
          isFix ? 'Fix and send again' : 'Edit',
          Icons.edit_outlined,
          hasDividerBefore: actions.isEmpty,
        ),
      );
    }
    if (canOpenHistory) {
      items.add(
        CardMenuItem(
          CardMenuItem.history,
          'History',
          Icons.history,
          hasDividerBefore: actions.isEmpty && !canEdit,
        ),
      );
    }
    if (canDelete) {
      items.add(
        const CardMenuItem(
          CardMenuItem.delete,
          'Delete',
          Icons.delete_outline,
          isDanger: true,
          hasDividerBefore: true,
        ),
      );
    }
    return items;
  }
}
