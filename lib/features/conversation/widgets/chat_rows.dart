import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';

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

/// "N new messages": a peach line with the count under it, placed at the
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
        border: Border(top: BorderSide(color: AppColors.peach)),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(color: AppColors.accentInk),
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
    child: Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accent,
        ),
      ),
    ),
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
