import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_anchored_popup.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../data/models/record_state.dart';
import '../../../data/repositories/ticket_repository.dart';
import '../models/card_menu.dart';
import '../tickets_texts.dart';

/// The menu of a form or record card: one list for the chat and the Work
/// Space. [itemsFor] makes the rows from what `record.actions` said (the menu
/// reads it when it opens, cached 60 s); while that read runs the record's
/// rows say "Loading…". A row that is off shows the server's reason and does
/// nothing. [onPick] gets every other row.
class RecordMenuRows extends StatelessWidget {
  const RecordMenuRows({
    super.key,
    required this.tickets,
    required this.recordId,
    required this.itemsFor,
    required this.onPick,
    this.leading = const [],
    this.isCompact = false,
  });

  final TicketRepository tickets;
  final int? recordId;
  final List<CardMenuItem> Function(RecordState? state) itemsFor;
  final void Function(CardMenuItem item) onPick;

  /// Rows above the menu (a failed card's Retry), outside the rule.
  final List<Widget> leading;

  /// The small popup look (Inbox): 44 px rows, an 18 px icon in a 24 px slot,
  /// no dividers between rows, one inset hairline above a destructive row.
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final id = recordId;
    if (id == null) return _column(null, false);
    return Obx(() => _column(tickets.stateOf(id), tickets.isCardReading(id)));
  }

  Widget _column(RecordState? state, bool isLoading) {
    final items = itemsFor(state);
    final isNote = isLoading || (items.isEmpty && leading.isEmpty);
    final count = items.length + (isNote ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...leading,
        for (final (i, item) in items.indexed)
          if (isCompact)
            AppPopupItem(
              index: i,
              count: count,
              hasDividerAbove: item.isDanger && item != items.first,
              child: _CompactRow(item: item, onPick: onPick),
            )
          else ...[
            if (item.hasDividerBefore)
              const Divider(height: 1, color: AppColors.cardLine),
            _row(item),
          ],
        if (isNote)
          _note(
            isLoading ? TicketsTexts.menuLoading : TicketsTexts.menuEmpty,
            index: items.length,
            count: count,
          ),
      ],
    );
  }

  Widget _note(String text, {required int index, required int count}) {
    final note = Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(text, style: AppText.readable),
    );
    return isCompact
        ? AppPopupItem(index: index, count: count, child: note)
        : note;
  }

  Widget _row(CardMenuItem item) {
    final color = item.isDanger
        ? AppColors.error
        : item.isEnabled
        ? AppColors.muted
        : AppColors.cardMuted;
    return AppListRow(
      title: item.label,
      subtitle: item.why.isEmpty ? null : item.why,
      minHeight: AppSpacing.settingRowHeight,
      titleStyle: AppText.rowTitle.copyWith(
        color: item.isDanger
            ? AppColors.error
            : item.isEnabled
            ? AppColors.ink
            : AppColors.cardMuted,
      ),
      leading: Icon(item.icon, size: 20, color: color),
      onTap: item.isEnabled ? () => onPick(item) : null,
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.item, required this.onPick});

  final CardMenuItem item;
  final void Function(CardMenuItem item) onPick;

  @override
  Widget build(BuildContext context) {
    final ink = item.isDanger
        ? AppColors.error
        : item.isEnabled
        ? AppColors.ink
        : AppColors.disabledInk;
    final iconInk = item.isDanger
        ? AppColors.error
        : item.isEnabled
        ? AppColors.muted
        : AppColors.disabledInk;
    return Semantics(
      container: true,
      button: true,
      enabled: item.isEnabled,
      label: item.why.isEmpty ? item.label : '${item.label}. ${item.why}',
      excludeSemantics: true,
      onTap: item.isEnabled ? () => onPick(item) : null,
      child: InkWell(
        onTap: item.isEnabled ? () => onPick(item) : null,
        highlightColor: AppColors.fill,
        splashColor: AppColors.fill,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.compactMenuRow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.compactMenuPadding,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: AppSpacing.compactMenuIconSlot,
                  child: Icon(
                    item.icon,
                    size: AppSpacing.compactMenuIcon,
                    color: iconInk,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        style: AppText.menuItem.copyWith(color: ink),
                      ),
                      if (item.why.isNotEmpty)
                        Text(
                          item.why,
                          style: AppText.caption.copyWith(color: ink),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
