import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/data/models/models.dart';
import '../tickets_texts.dart';

/// A subtle tinted pill with a small icon: [icon] and [tone] come from
/// where the ticket stands.
class TicketPill extends StatelessWidget {
  const TicketPill({
    super.key,
    required this.label,
    required this.icon,
    required this.tone,
    this.hasDot = false,
    this.leading,
  });

  final String label;
  final IconData icon;
  final AppTone tone;

  /// A small dot instead of the icon.
  final bool hasDot;

  /// Shown instead of the icon and the dot, e.g. a small progress arc.
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
    decoration: BoxDecoration(
      color: tone.tint,
      borderRadius: AppRadius.pillAll,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null)
          leading!
        else if (hasDot)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: tone.solid,
              shape: BoxShape.circle,
            ),
          )
        else
          Icon(icon, size: 13, color: tone.strong),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(color: tone.strong, height: 1.2),
          ),
        ),
      ],
    ),
  );
}

/// The status of a ticket: the data decides first (a final status is done,
/// the status a record starts at is open), then words refine it (a returned
/// or dropped status).
class TicketStatusPill extends StatelessWidget {
  const TicketStatusPill({
    super.key,
    required this.ticket,
    this.status,
    this.isFinal,
    this.first,
  });

  final Ticket ticket;

  /// What `record.actions` says now, when the screen has it: it wins over the
  /// value stored in the record.
  final String? status;
  final bool? isFinal;
  final String? first;

  static AppTone toneOf(
    Ticket t, {
    String? status,
    bool? isFinal,
    String? first,
  }) {
    if (t.isAwaitingApproval) return AppTones.slate;
    final shown = status ?? t.status;
    final done = isFinal ?? t.isFinal;
    final start = first ?? t.table?.firstStatus;
    if (start == null && t.table == null && status == null) {
      return AppTones.slate;
    }
    return toneOfStatus(shown, isFinal: done, first: start);
  }

  /// The tone of a status name alone: green when final, red when dropped,
  /// blue at the first status, violet in between. The header pill and the
  /// history pills share it.
  static AppTone toneOfStatus(
    String shown, {
    required bool isFinal,
    String? first,
  }) {
    final done = isFinal;
    final start = first;
    final name = shown.toLowerCase();
    if (done) return _isLost(name) ? AppTones.red : AppTones.green;
    if (name.contains('return') || name.contains('revert')) {
      return AppTones.violet;
    }
    return shown == start ? AppTones.blue : AppTones.violet;
  }

  static bool _isLost(String name) =>
      name.contains('drop') ||
      name.contains('cancel') ||
      name.contains('reject') ||
      name.contains('withdraw');

  @override
  Widget build(BuildContext context) => TicketPill(
    label: ticket.isAwaitingApproval
        ? TicketsTexts.waitingForApproval
        : status ?? ticket.status,
    icon: Icons.circle,
    tone: toneOf(ticket, status: status, isFinal: isFinal, first: first),
    hasDot: true,
  );
}
