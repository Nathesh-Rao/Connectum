import 'package:flutter/material.dart';

import '../../../core/widgets/app_tag.dart';
import '../../../data/models/ticket.dart';
import '../tickets_texts.dart';

/// The status of a ticket as a chip. The tone comes from the data, never from
/// a name: a final status is drawn as done, the status a record starts at is
/// neutral, any other status is accent.
class TicketStatusChip extends StatelessWidget {
  const TicketStatusChip({super.key, required this.ticket});

  final Ticket ticket;

  static AppTagTone toneOf(Ticket t) {
    if (t.isAwaitingApproval) return AppTagTone.neutral;
    final table = t.table;
    if (table == null) return AppTagTone.neutral;
    if (t.isFinal) return AppTagTone.done;
    return t.status == table.firstStatus
        ? AppTagTone.neutral
        : AppTagTone.accent;
  }

  @override
  Widget build(BuildContext context) => AppTag(
    label: ticket.isAwaitingApproval
        ? TicketsTexts.waitingForApproval
        : ticket.status,
    tone: toneOf(ticket),
  );
}
