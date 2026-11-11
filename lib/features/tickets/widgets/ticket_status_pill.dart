import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../data/models/ticket.dart';
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
  });

  final String label;
  final IconData icon;
  final AppTone tone;

  /// A small dot instead of the icon.
  final bool hasDot;

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
        if (hasDot)
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
  const TicketStatusPill({super.key, required this.ticket});

  final Ticket ticket;

  static AppTone toneOf(Ticket t) {
    if (t.isAwaitingApproval) return AppTones.slate;
    final table = t.table;
    if (table == null) return AppTones.slate;
    final name = t.status.toLowerCase();
    if (t.isFinal) {
      return _isLost(name) ? AppTones.red : AppTones.green;
    }
    if (name.contains('return') || name.contains('revert')) {
      return AppTones.orange;
    }
    return t.status == table.firstStatus ? AppTones.blue : AppTones.orange;
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
        : ticket.status,
    icon: Icons.circle,
    tone: toneOf(ticket),
    hasDot: true,
  );
}
