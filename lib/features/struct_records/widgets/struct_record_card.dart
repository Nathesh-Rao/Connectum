import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';

/// One record: the title and "No. 12", the first fields as key/value
/// rows, a pill when it waits for approval or was declined, and Edit and
/// Delete only when [onEdit] / [onDelete] are given. Tapping it does nothing.
class StructRecordCard extends StatelessWidget {
  const StructRecordCard({
    super.key,
    required this.data,
    this.onEdit,
    this.onDelete,
    this.isBusy = false,
  });

  final StructRecordCardData data;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Record ${data.id}, ${data.title}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: AppColors.cardLine),
          boxShadow: AppShadows.card,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: AppText.bodyStrong,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('No. ${data.id}', style: AppText.caption),
                        ],
                      ),
                    ),
                  ),
                  if (data.approval.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: _ApprovalPill(text: data.approval),
                    ),
                  ],
                  if (onEdit != null)
                    AppButton.icon(
                      icon: Icons.edit_outlined,
                      semanticLabel: 'Edit record ${data.id}',
                      onPressed: isBusy ? null : onEdit,
                    ),
                  if (onDelete != null)
                    AppButton.icon(
                      icon: Icons.delete_outline,
                      semanticLabel: 'Delete record ${data.id}',
                      onPressed: isBusy ? null : onDelete,
                    ),
                ],
              ),
              if (data.pairs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      for (final p in data.pairs)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xxs,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  p.label,
                                  style: AppText.readable,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  p.value,
                                  style: AppText.readableStrong,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalPill extends StatelessWidget {
  const _ApprovalPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDeclined = text == 'Declined';
    return Container(
      height: AppSpacing.statusPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDeclined ? AppColors.noFill : AppColors.violetTint,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        text,
        style: AppText.label.copyWith(
          color: isDeclined ? AppColors.noText : AppColors.violetStrong,
        ),
      ),
    );
  }
}
