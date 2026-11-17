import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/models/record_live.dart';
import '../tickets_texts.dart';

/// Where a record stands, under its card's fields (the web's `RecordStatus`):
/// the status chip, who it is with, how far it is, and the last update with
/// who made it. Nothing for a record that was never sent and has no status.
class RecordStatusBlock extends StatelessWidget {
  const RecordStatusBlock({super.key, required this.live, this.now});

  final RecordLive live;

  /// For tests: the clock the "when" of the last update is shown against.
  final DateTime? now;

  static String whenOf(int ts, DateTime now) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final time = ChatTime.time(ts);
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return time;
    }
    return '${ChatTime.date(ts)}, $time';
  }

  @override
  Widget build(BuildContext context) {
    if (!live.isShown) return const SizedBox.shrink();
    final pct = live.completion;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (live.status.isNotEmpty)
                AppTag(
                  label: live.status,
                  tone: live.isFinal ? AppTagTone.done : AppTagTone.accent,
                ),
              if (live.isSent && (live.holder.isNotEmpty || live.isShared))
                Text(
                  live.withText,
                  style: AppText.caption.copyWith(color: AppColors.cardMuted),
                ),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Expanded(child: AppProgressBar(value: pct / 100)),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  TicketsTexts.percentValue(pct),
                  style: AppText.caption.copyWith(color: AppColors.cardMuted),
                ),
              ],
            ),
          ],
          if (live.hasLast) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                if (live.lastBy.isNotEmpty)
                  Text(
                    '@${live.lastBy}',
                    style: AppText.caption.copyWith(color: AppColors.ink),
                  ),
                const Spacer(),
                if (live.lastTs > 0)
                  Text(
                    whenOf(live.lastTs, now ?? DateTime.now()),
                    style: AppText.caption.copyWith(color: AppColors.cardMuted),
                  ),
              ],
            ),
            if (live.lastRemarks.isNotEmpty)
              Text(
                live.lastRemarks,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppText.readable,
              ),
          ],
        ],
      ),
    );
  }
}
