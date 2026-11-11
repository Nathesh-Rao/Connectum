import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../models/ticket_detail_row.dart';

/// The record as a flat list: a soft icon chip, the label above the value,
/// and a hairline inset past the chip.
class TicketDetailList extends StatelessWidget {
  const TicketDetailList({super.key, required this.rows});

  final List<TicketDetailRow> rows;

  static const chip = 36.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          _Row(row: rows[i], hasDivider: i > 0),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row, required this.hasDivider});

  final TicketDetailRow row;
  final bool hasDivider;

  @override
  Widget build(BuildContext context) {
    final tone = row.priority;
    return Column(
      children: [
        if (hasDivider)
          const Padding(
            padding: EdgeInsets.only(
              left: TicketDetailList.chip + AppSpacing.sm,
            ),
            child: Divider(height: 1, color: AppColors.line),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: TicketDetailList.chip,
                height: TicketDetailList.chip,
                decoration: BoxDecoration(
                  color: AppTones.slate.tint,
                  borderRadius: AppRadius.controlAll,
                ),
                child: Icon(row.icon, size: 18, color: AppTones.slate.strong),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: AppText.readable.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: 2),
                    if (tone != null)
                      _PriorityPill(label: row.value, tone: tone)
                    else
                      Text(row.value, style: AppText.body),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.label, required this.tone});

  final String label;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
    decoration: BoxDecoration(
      color: tone.tint,
      borderRadius: AppRadius.pillAll,
    ),
    child: Text(
      label,
      style: AppText.label.copyWith(color: tone.strong, height: 1.2),
    ),
  );
}
