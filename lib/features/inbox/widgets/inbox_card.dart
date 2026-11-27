import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'package:connectum/features/tickets/tickets.dart';
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
/// Update status and History, read when it opens, as a callout under the dots.
/// While `record.actions` is read the menu says "Loading…" and follows the
/// answer. A row that is off shows the server's reason and does nothing.
class InboxMenu {
  InboxMenu._();

  static List<MenuItem<CardMenuItem>> _rows(InboxController c, InboxRow row) {
    final tickets = c.tickets;
    return rowsFor(
      CardMenu.build(record: tickets.stateOf(row.id), canOpenHistory: true),
      isLoading: tickets.isCardReading(row.id),
    );
  }

  /// The callout's rows of a card's menu: a destructive row gets the hairline
  /// above it, and a note says "Loading…" while the read runs (or that
  /// nothing is offered).
  static List<MenuItem<CardMenuItem>> rowsFor(
    List<CardMenuItem> items, {
    bool isLoading = false,
  }) => [
    for (final (i, item) in items.indexed)
      MenuItem<CardMenuItem>(
        label: item.label,
        icon: item.icon,
        value: item,
        why: item.why,
        isEnabled: item.isEnabled,
        isDanger: item.isDanger,
        hasDividerAbove: item.isDanger && i > 0,
      ),
    if (isLoading || items.isEmpty)
      MenuItem<CardMenuItem>.note(
        isLoading ? TicketsTexts.menuLoading : TicketsTexts.menuEmpty,
      ),
  ];

  static Future<void> show(
    BuildContext context,
    InboxController c,
    InboxRow row,
  ) async {
    final anchor = AnimatedCalloutMenu.anchorOf(context);
    if (anchor == null) return;
    final root = Navigator.of(context, rootNavigator: true).context;
    c.openMenu(row);
    final live = ValueNotifier(_rows(c, row));
    var isOpen = true;
    // A turn later: the read still counts as running while it announces that
    // it is done.
    final worker = ever(c.tickets.cardRevision, (_) {
      Future(() {
        if (isOpen) live.value = _rows(c, row);
      });
    });
    final CardMenuItem? item;
    try {
      item = await AnimatedCalloutMenu.show<CardMenuItem>(
        context,
        anchor,
        live.value,
        label: 'Record menu',
        live: live,
      );
    } finally {
      isOpen = false;
      worker.dispose();
      live.dispose();
    }
    if (item == null) return;
    if (item.id == CardMenuItem.history) {
      c.open(row);
    } else if (item.isRecordAction && root.mounted) {
      TicketActionSheet.show(root, c.detailOf(row), item.recordActionId);
    }
  }
}
