import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_anchored_popup.dart';
import '../../../core/widgets/app_button.dart';
import '../../smart_view/widgets/sv_file_preview_dialog.dart';
import '../../tickets/models/card_menu.dart';
import '../../tickets/widgets/record_card_actions.dart';
import '../../tickets/widgets/record_menu_rows.dart';
import '../../tickets/widgets/ticket_action_sheet.dart';
import '../inbox_controller.dart';
import '../inbox_tour_demo.dart';
import '../models/inbox_card_rows.dart';
import '../models/inbox_record_tone.dart';
import '../models/inbox_row.dart';
import 'inbox_avatar_ring.dart';
import 'inbox_card_frame.dart';

/// The colours of each state, from the theme's tones (never a hex here).
AppTone inboxToneOf(InboxState s) => switch (s) {
  InboxState.completed => AppTones.green,
  InboxState.rejected => AppTones.red,
  InboxState.waiting => AppTones.violet,
  InboxState.pending => AppTones.yellow,
  InboxState.assigned => AppTones.blue,
};

AppTone inboxPriorityToneOf(InboxPriority p) => switch (p) {
  InboxPriority.high => AppTones.red,
  InboxPriority.medium => AppTones.teal,
  InboxPriority.low => AppTones.slate,
};

String inboxPriorityWord(InboxPriority p) => switch (p) {
  InboxPriority.high => 'High priority',
  InboxPriority.medium => 'Medium priority',
  InboxPriority.low => 'Low priority',
};

/// One record of the Inbox as a card (`InboxCardFrame`): the person's face,
/// the form, the person's name, `#id`, date and time; the status circle, the
/// priority and the menu (only with an action); the status as a pill; the
/// answers as rows with an icon.
class InboxCard extends StatelessWidget {
  const InboxCard({
    super.key,
    required this.controller,
    required this.row,
    this.sample,
  });

  final InboxController controller;
  final InboxRow row;

  /// The first-run tour's sample: the card is drawn from [row] alone. It
  /// reads no record state, asks the server nothing, has no menu and does
  /// nothing on a tap; its open state is the sample's own.
  final InboxTourDemo? sample;

  Widget _sampleCard(InboxTourDemo demo) {
    final state = row.stateFor('');
    final name = row.who.isEmpty
        ? ''
        : '${row.who[0].toUpperCase()}${row.who.substring(1)}';
    final priority = row.priority;
    final key = 'r${row.id}';
    return Obx(
      () => InboxCardFrame(
        leading: InboxAvatarRing(name: name),
        title: row.form,
        name: name,
        idText: '#${row.id.abs()}',
        ts: row.ts,
        status: InboxCardStatus.of(state),
        statusLabel: inboxStateWords[state] ?? '',
        strip: row.chipText(null),
        priorityTone: priority == null ? null : inboxPriorityToneOf(priority),
        priorityLabel: priority == null ? '' : inboxPriorityWord(priority),
        rows: inboxCardRows(row),
        isFilesOpen: (name) => demo.isOpen('f${row.id}:$name'),
        onToggleFiles: (name) => demo.toggle('f${row.id}:$name'),
        isExpanded: demo.isOpen(key),
        onToggle: () => demo.toggle(key),
        onTap: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final demo = sample;
    if (demo != null) return _sampleCard(demo);
    final c = controller;
    final state = row.stateFor(c.me);
    final live = c.tickets.liveOf(row.id);
    final priority = row.priority;
    final key = 'r${row.id}';
    return RecordOnScreen(
      recordId: row.id,
      tickets: c.tickets,
      summary: c.summaryOf(row),
      child: Obx(() {
        final v = live.value;
        final name = c.whoLabelOf(row);
        final hasMenu = c.tickets.itemsOf(row.id).isNotEmpty;
        return InboxCardFrame(
          leading: InboxAvatarRing(name: name, picture: c.pictureOf(row)),
          title: row.form,
          name: name,
          idText: '#${row.id}',
          ts: row.ts,
          status: InboxCardStatus.of(state),
          statusLabel: inboxStateWords[state] ?? '',
          strip: row.chipText(v.isKnown ? v.status : null),
          priorityTone: priority == null ? null : inboxPriorityToneOf(priority),
          priorityLabel: priority == null ? '' : inboxPriorityWord(priority),
          menu: hasMenu ? _Menu(controller: c, row: row) : null,
          rows: inboxCardRows(row, typeOf: (f) => c.fieldTypeOf(row, f)),
          onOpenFiles: c.hasFiles
              ? (files, index) => SvFilePreviewDialog.show(
                  context,
                  c.newFilePreview(files, index),
                )
              : null,
          isFilesOpen: (name) => c.isCardExpanded('f${row.id}:$name'),
          onToggleFiles: (name) => c.toggleCardExpanded('f${row.id}:$name'),
          isExpanded: c.isCardExpanded(key),
          onToggle: () => c.toggleCardExpanded(key),
          onTap: () => c.open(row),
        );
      }),
    );
  }
}

/// The three dots, drawn only for a record the server lets the person act on.
class _Menu extends StatelessWidget {
  const _Menu({required this.controller, required this.row});

  final InboxController controller;
  final InboxRow row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.inboxMenuButton,
      height: AppSpacing.inboxMenuButton,
      child: FittedBox(
        child: AppButton.icon(
          icon: Icons.more_horiz,
          semanticLabel: 'Record menu',
          onPressed: () => InboxMenu.show(context, controller, row),
        ),
      ),
    );
  }
}

/// The record menu of a card (the one of the chat and the Work Space): Send,
/// Update status and History, read when it opens, as a popup under the dots.
class InboxMenu {
  InboxMenu._();

  static Future<void> show(
    BuildContext context,
    InboxController c,
    InboxRow row,
  ) {
    c.openMenu(row);
    return AppAnchoredPopup.show(
      context,
      label: 'Record menu',
      builder: (popup) => RecordMenuRows(
        isCompact: true,
        tickets: c.tickets,
        recordId: row.id,
        itemsFor: (state) =>
            CardMenu.build(record: state, canOpenHistory: true),
        onPick: (item) {
          final root = Navigator.of(popup, rootNavigator: true).context;
          Navigator.of(popup, rootNavigator: true).pop();
          if (item.id == CardMenuItem.history) {
            c.open(row);
          } else if (item.isRecordAction) {
            TicketActionSheet.show(root, c.detailOf(row), item.recordActionId);
          }
        },
      ),
    );
  }
}
