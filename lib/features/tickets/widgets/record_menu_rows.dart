import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
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
  });

  final TicketRepository tickets;
  final int? recordId;
  final List<CardMenuItem> Function(RecordState? state) itemsFor;
  final void Function(CardMenuItem item) onPick;

  /// Rows above the menu (a failed card's Retry), outside the rule.
  final List<Widget> leading;

  @override
  Widget build(BuildContext context) {
    final id = recordId;
    if (id == null) return _column(null, false);
    return Obx(() => _column(tickets.stateOf(id), tickets.isCardReading(id)));
  }

  Widget _column(RecordState? state, bool isLoading) {
    final items = itemsFor(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...leading,
        for (final item in items) ...[
          if (item.hasDividerBefore)
            const Divider(height: 1, color: AppColors.cardLine),
          _row(item),
        ],
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(TicketsTexts.menuLoading, style: AppText.readable),
          )
        else if (items.isEmpty && leading.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(TicketsTexts.menuEmpty, style: AppText.readable),
          ),
      ],
    );
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
