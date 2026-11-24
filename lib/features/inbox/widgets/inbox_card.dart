import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../tickets/models/card_menu.dart';
import '../../tickets/widgets/record_card_actions.dart';
import '../../tickets/widgets/record_menu_rows.dart';
import '../../tickets/widgets/ticket_action_sheet.dart';
import '../inbox_controller.dart';
import '../models/inbox_card_rows.dart';
import '../models/inbox_record_tone.dart';
import '../models/inbox_row.dart';

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

/// One record of the Inbox, as on the web (`RecordFrame`): a tinted band with
/// the person, the form, the number and time, the status and the priority; a
/// body of name and value lines that scrolls inside a fixed card height.
class InboxCard extends StatelessWidget {
  const InboxCard({super.key, required this.controller, required this.row});

  final InboxController controller;
  final InboxRow row;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final tone = inboxToneOf(row.stateFor(c.me));
    return RecordOnScreen(
      recordId: row.id,
      tickets: c.tickets,
      summary: c.summaryOf(row),
      child: Semantics(
        container: true,
        child: Material(
          color: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardAll,
            side: const BorderSide(color: AppColors.cardLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => c.open(row),
            child: SizedBox(
              height: AppSpacing.inboxCardHeight * scale,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Band(controller: c, row: row, tone: tone),
                  const Divider(height: 1, color: AppColors.cardLine),
                  Expanded(child: _Body(row: row)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.controller, required this.row, required this.tone});

  final InboxController controller;
  final InboxRow row;
  final AppTone tone;

  String get _byline {
    final id = '#${row.id}';
    if (row.ts <= 0) return id;
    return '$id · ${ChatTime.date(row.ts)}, ${ChatTime.time(row.ts)}';
  }

  @override
  Widget build(BuildContext context) {
    final priority = row.priority;
    return ColoredBox(
      color: tone.tintMedium,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Face(controller: controller, row: row),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.form,
                    style: AppText.bodyStrong.copyWith(color: AppColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _byline,
                    style: AppText.caption.copyWith(color: AppColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.inboxChipMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (priority != null) _PriorityDot(priority: priority),
                      _Menu(controller: controller, row: row),
                    ],
                  ),
                  _StatusChip(controller: controller, row: row, tone: tone),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.controller, required this.row});

  final InboxController controller;
  final InboxRow row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.inboxFaceWidth,
      child: Obx(() {
        final name = controller.whoLabelOf(row);
        return Column(
          children: [
            AppAvatar(
              name: name,
              size: AppSpacing.inboxFaceSize,
              picture: controller.pictureOf(row),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              name,
              style: AppText.caption.copyWith(color: AppColors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        );
      }),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final InboxPriority priority;

  @override
  Widget build(BuildContext context) {
    final word = inboxPriorityWord(priority);
    return Semantics(
      label: word,
      child: Tooltip(
        message: word,
        child: Container(
          width: AppSpacing.inboxPriorityDot,
          height: AppSpacing.inboxPriorityDot,
          margin: const EdgeInsets.only(right: AppSpacing.xxs),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: inboxPriorityToneOf(priority).solid,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.controller,
    required this.row,
    required this.tone,
  });

  final InboxController controller;
  final InboxRow row;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final live = controller.tickets.liveOf(row.id);
    return Obx(() {
      final v = live.value;
      final text = row.chipText(v.isKnown ? v.status : null);
      if (text.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(right: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: tone.tintStrong,
          borderRadius: AppRadius.pillAll,
        ),
        child: Text(
          text,
          style: AppText.readableStrong.copyWith(color: tone.strong),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    });
  }
}

/// The three dots: only for a record the server lets the person act on.
class _Menu extends StatelessWidget {
  const _Menu({required this.controller, required this.row});

  final InboxController controller;
  final InboxRow row;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (c.tickets.itemsOf(row.id).isEmpty) {
        return const SizedBox(height: AppSpacing.inboxMenuButton);
      }
      return SizedBox(
        width: AppSpacing.inboxMenuButton,
        height: AppSpacing.inboxMenuButton,
        child: FittedBox(
          child: AppButton.icon(
            icon: Icons.more_horiz,
            semanticLabel: 'Record menu',
            onPressed: () => InboxMenu.show(context, c, row),
          ),
        ),
      );
    });
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.row});

  final InboxRow row;

  @override
  Widget build(BuildContext context) {
    final rows = inboxCardRows(row);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      r.$1,
                      style: AppText.readable.copyWith(color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    flex: 7,
                    child: Text(
                      r.$2,
                      style: AppText.readable.copyWith(color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The record menu of a card (the one of the chat and the Work Space): Send,
/// Update status and History, read when it opens.
class InboxMenu {
  InboxMenu._();

  static Future<void> show(
    BuildContext context,
    InboxController c,
    InboxRow row,
  ) {
    c.openMenu(row);
    return AppBottomSheet.show<void>(
      context,
      title: 'Record',
      child: Builder(
        builder: (sheet) => RecordMenuRows(
          tickets: c.tickets,
          recordId: row.id,
          itemsFor: (state) =>
              CardMenu.build(record: state, canOpenHistory: true),
          onPick: (item) {
            final root = Navigator.of(sheet, rootNavigator: true).context;
            Navigator.of(sheet).pop();
            if (item.id == CardMenuItem.history) {
              c.open(row);
            } else if (item.isRecordAction) {
              TicketActionSheet.show(root, c.detailOf(row), item.recordActionId);
            }
          },
        ),
      ),
    );
  }
}
