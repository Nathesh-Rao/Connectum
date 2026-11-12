import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_spinner.dart';

/// "Today", "Yesterday", a weekday or a date, centred between messages.
class DayDivider extends StatelessWidget {
  const DayDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Center(child: Text(label, style: AppText.caption)),
  );
}

/// "N new messages": a blue line with the count under it, placed at the
/// first unread message when the conversation opened.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Container(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.primaryTintStrong)),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(color: AppColors.primaryStrong),
      ),
    ),
  );
}

/// The top of the list: a spinner while older messages load.
class LoadingOlderRow extends StatelessWidget {
  const LoadingOlderRow({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Center(child: AppSpinner()),
  );
}

/// The top of the list once there is nothing older.
class StartRow extends StatelessWidget {
  const StartRow({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Center(
      child: Text('Beginning of conversation', style: AppText.caption),
    ),
  );
}

/// Older messages could not be loaded: the cached ones stay, this row retries.
class OlderErrorRow extends StatelessWidget {
  const OlderErrorRow({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Column(
      children: [
        const Text("Couldn't load older messages", style: AppText.caption),
        AppButton.text(label: 'Retry', onPressed: onRetry),
      ],
    ),
  );
}

/// A small centred line of my own that is not a message: the answer of a `#`
/// command, or "Sent to @name" in the workspace (which opens that chat).
class SystemRow extends StatelessWidget {
  const SystemRow({super.key, required this.text, this.onTap, this.isProblem});

  final String text;
  final VoidCallback? onTap;
  final bool? isProblem;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: const BoxDecoration(
            color: AppColors.bubbleIn,
            borderRadius: AppRadius.controlAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(
                    color: isProblem == true ? AppColors.error : null,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: AppColors.muted,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
