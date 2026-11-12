import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../data/models/ticket.dart';
import '../models/ticket_text.dart';
import '../tickets_texts.dart';

/// The updates of a ticket, oldest first: the action, who did it, the
/// status it went from and to, and what was said.
class TicketHistoryTimeline extends StatelessWidget {
  const TicketHistoryTimeline({
    super.key,
    required this.entries,
    required this.nameOf,
  });

  final List<TicketHistoryEntry> entries;
  final String Function(String user) nameOf;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          _Step(
            entry: entries[i],
            isLast: i == entries.length - 1,
            nameOf: nameOf,
            now: now,
          ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.entry,
    required this.isLast,
    required this.nameOf,
    required this.now,
  });

  final TicketHistoryEntry entry;
  final bool isLast;
  final String Function(String user) nameOf;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final move = [
      if (e.fromStatus.isNotEmpty) e.fromStatus,
      if (e.toStatus.isNotEmpty) e.toStatus,
    ].join(' → ');
    final details = <String>[
      if (e.sentTo.isNotEmpty) '${TicketsTexts.sentTo} ${nameOf(e.sentTo)}',
      if (e.percent.isNotEmpty)
        TicketsTexts.percentValue(int.tryParse(e.percent) ?? 0),
      if (e.reason.isNotEmpty) '${TicketsTexts.reasonLabel}: ${e.reason}',
    ];
    final ago = TicketText.ago(e.ts, now);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: AppSpacing.md,
            child: Column(
              children: [
                const SizedBox(height: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryBright,
                  ),
                ),
                if (!isLast)
                  Expanded(child: Container(width: 1, color: AppColors.line)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.action.isEmpty ? move : e.action,
                    style: AppText.bodyStrong,
                  ),
                  Text(
                    [
                      nameOf(e.by),
                      if (e.isByAdmin) TicketsTexts.byAdmin,
                      if (ago.isNotEmpty) ago,
                    ].join(' · '),
                    style: AppText.rowCaption,
                  ),
                  if (move.isNotEmpty && e.action.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Text(move, style: AppText.readable),
                    ),
                  for (final line in details)
                    Text(line, style: AppText.readable),
                  if (e.remarks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Text(e.remarks, style: AppText.body),
                    ),
                  if (e.files.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.attach_file,
                            size: 14,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Expanded(
                            child: Text(
                              e.files.map((f) => f.name).join(', '),
                              style: AppText.readable,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
