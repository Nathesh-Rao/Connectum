import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/data/models/models.dart';

/// The bar above the field while a note is being edited ("Editing note") or
/// quoted ("Replying to note"), with the note's first line and a cancel. It
/// takes the room of its text and never overflows at a large text scale: the
/// lines are cut with an ellipsis.
class WorkspaceContextBar extends StatelessWidget {
  const WorkspaceContextBar({
    super.key,
    required this.message,
    required this.label,
    required this.cancelLabel,
    required this.onCancel,
  });

  final Message? message;
  final String label;
  final String cancelLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return AnimatedSize(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: m == null
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                0,
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xxs,
                AppSpacing.xs,
              ),
              decoration: const BoxDecoration(
                color: AppColors.bubbleIn,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppRadius.control),
                ),
                border: Border(
                  left: BorderSide(color: AppColors.primaryBright, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label.copyWith(
                            color: AppColors.primaryStrong,
                          ),
                        ),
                        Text(
                          AttachmentTag.preview(m.text) ?? m.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: cancelLabel,
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: onCancel,
                      child: const SizedBox(
                        width: AppSpacing.composerButton,
                        height: AppSpacing.composerButton,
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
