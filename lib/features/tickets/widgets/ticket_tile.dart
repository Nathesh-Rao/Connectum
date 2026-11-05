import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../data/models/ticket.dart';
import '../models/ticket_text.dart';
import '../tickets_texts.dart';
import 'ticket_status_chip.dart';

/// One ticket in a list: title, `<caption> #<id>`, the status, who it is with,
/// the completion when it has started, and how long ago it was raised.
class TicketTile extends StatelessWidget {
  const TicketTile({
    super.key,
    required this.ticket,
    required this.withName,
    required this.onTap,
  });

  final Ticket ticket;

  /// Who it is with, as a name (or "you").
  final String withName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final completion = t.completion;
    final ago = TicketText.ago(t.ts, DateTime.now());
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowTitle,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(t.ref, style: AppText.rowCaption),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TicketStatusChip(ticket: t),
                  if (!t.isAwaitingApproval)
                    Text(
                      '${TicketsTexts.withLabel} $withName',
                      style: AppText.readable.copyWith(color: AppColors.muted),
                    ),
                  if (ago.isNotEmpty)
                    Text(
                      ago,
                      style: AppText.readable.copyWith(color: AppColors.muted),
                    ),
                ],
              ),
              if (completion > 0 && !t.isAwaitingApproval) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(child: AppProgressBar(value: completion / 100)),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      TicketsTexts.percentValue(completion),
                      style: AppText.caption,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
