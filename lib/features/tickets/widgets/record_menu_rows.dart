import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/data/repositories/repositories.dart';
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
    final isNote = isLoading || (items.isEmpty && leading.isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...leading,
        for (final item in items) ...[
          if (item.hasDividerBefore)
            const Divider(height: 1, color: AppColors.cardLine),
          _row(item),
        ],
        if (isNote)
          _note(isLoading ? TicketsTexts.menuLoading : TicketsTexts.menuEmpty),
      ],
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: Text(text, style: AppText.readable),
  );

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
