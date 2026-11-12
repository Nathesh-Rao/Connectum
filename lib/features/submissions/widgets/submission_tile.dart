import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/app_key_value_row.dart';
import '../models/submission_row.dart';

/// One submission in the list: its form, number and date, the first few
/// values, and a link to the detail.
class SubmissionTile extends StatefulWidget {
  const SubmissionTile({super.key, required this.row, required this.onTap});

  final SubmissionRow row;
  final VoidCallback onTap;

  @override
  State<SubmissionTile> createState() => _SubmissionTileState();
}

class _SubmissionTileState extends State<SubmissionTile> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (!mounted || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.row.card;
    final now = DateTime.now();
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.985 : 1,
          duration: AppDurations.fast,
          curve: AppCurves.out,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.lg),
              ),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (card.status != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.badge),
                      ),
                    ),
                    child: Text(
                      card.status!,
                      style: AppText.label.copyWith(color: AppColors.primaryStrong),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  card.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${card.label} · ${ChatTime.day(card.ts, now)}, '
                  '${ChatTime.time(card.ts)}',
                  style: AppText.caption,
                ),
                if (widget.row.preview.isNotEmpty)
                  const SizedBox(height: AppSpacing.sm),
                for (var i = 0; i < widget.row.preview.length; i++)
                  AppKeyValueRow(entry: widget.row.preview[i]),
                const SizedBox(height: AppSpacing.xs),
                Text('View details →', style: AppText.action),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
