import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_animated_size.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/smart_view/sv_columns.dart';
import 'sv_col_icon.dart';
import 'smart_view_status_pill.dart';

/// One record as a read-only card: title and record status, a quiet meta row
/// (No., who, when, the linked status), then the structure's own fields as
/// icon, label and value. Up to [maxFields] show; more are behind a
/// "Show all (N)" row that grows the card. No buttons, no progress, no menu.
class SmartViewCard extends StatelessWidget {
  const SmartViewCard({
    super.key,
    required this.data,
    required this.isExpanded,
    required this.onToggle,
    this.onTap,
    this.version = 0,
  });

  static const maxFields = 6;
  static const _labelWidth = 92.0;

  final SvCardData data;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onTap;
  final int version;

  @override
  Widget build(BuildContext context) {
    final fields = data.fields;
    final hasMore = fields.length > maxFields;
    final shown = hasMore && !isExpanded
        ? fields.take(maxFields).toList()
        : fields;
    final card = RepaintBoundary(
      child: Semantics(
        container: true,
        label: 'Record ${data.number}, ${data.title}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: AppColors.cardLine),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          data.title,
                          style: AppText.rowTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      SmartViewStatusPill(label: data.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _MetaRow(data: data),
                  if (fields.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(height: 1, color: AppColors.line),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  AppAnimatedSize(
                    duration: AppDurations.sheetResize,
                    curve: AppCurves.out,
                    alignment: Alignment.topCenter,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < shown.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              top: i == 0 ? 0 : AppSpacing.sm,
                            ),
                            child: _FieldRow(
                              column: shown[i].column,
                              cell: shown[i].cell,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasMore)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton.text(
                        label: isExpanded
                            ? 'Show less'
                            : 'Show all (${fields.length})',
                        onPressed: onToggle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (version == 0) return card;
    return TweenAnimationBuilder<double>(
      key: ValueKey('fade-${data.number}-$version'),
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.reduced,
      curve: AppCurves.out,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: card,
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.data});

  final SvCardData data;

  @override
  Widget build(BuildContext context) {
    final quiet = AppText.caption.copyWith(color: AppColors.cardMuted);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('No. ${data.number}', style: quiet),
        Text('·', style: quiet),
        Text(data.by, style: quiet),
        Text('·', style: quiet),
        Text(data.submitted, style: quiet),
        if (data.ticketStatus.isNotEmpty)
          SmartViewStatusPill(label: data.ticketStatus),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.column, required this.cell});

  final SvColumn column;
  final SvCellValue cell;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            SvColIcon.of(column.type),
            size: 16,
            color: AppColors.cardMuted,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: SmartViewCard._labelWidth,
          child: Text(
            column.label,
            style: AppText.caption.copyWith(color: AppColors.cardMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Semantics(
            label: cell.isEmpty ? 'empty' : null,
            child: Text(
              cell.text,
              style: AppText.readable.copyWith(
                color: cell.isEmpty ? AppColors.cardMuted : AppColors.ink,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
