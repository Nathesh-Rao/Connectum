import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/app_button.dart';
import '../models/feed_item.dart';
import '../notification_router.dart';
import '../notification_texts.dart';

enum FeedTileMenu { toggleRead, resolve, dismiss }

/// One feed item: icon tinted by priority, title, clipped message, time, a
/// count when the server folded several into one, an unread dot and an
/// optional action button.
class FeedTile extends StatelessWidget {
  const FeedTile({
    super.key,
    required this.item,
    required this.readText,
    required this.onTap,
    required this.onMenu,
    required this.onDismissed,
  });

  final FeedItem item;

  /// The words to show: the message, or for an end-to-end item the opened
  /// text (null while it cannot be read).
  final Future<String?> Function(FeedItem item) readText;
  final VoidCallback onTap;
  final ValueChanged<FeedTileMenu> onMenu;
  final VoidCallback onDismissed;

  static const double _iconBox = 40;

  static const _icons = {
    'chat': Icons.chat_bubble_outline,
    'alternate_email': Icons.alternate_email,
    'alarm': Icons.alarm,
    'task_alt': Icons.task_alt,
    'fact_check': Icons.fact_check_outlined,
    'approval': Icons.approval,
    'security': Icons.shield_outlined,
    'lock': Icons.lock_outline,
    'campaign': Icons.campaign_outlined,
    'group': Icons.group_outlined,
    'description': Icons.description_outlined,
    'confirmation_number': Icons.confirmation_number_outlined,
    'api': Icons.api,
  };

  (Color, Color) get _tint => switch (item.priority) {
    'high' => (AppColors.accentTint, AppColors.accent),
    'medium' => (AppColors.sand, AppColors.accentInk),
    'resolved' => (AppColors.yesFill, AppColors.yesText),
    _ => (AppColors.noFill, AppColors.noText),
  };

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = _tint;
    final destination = NotificationRouter.resolve(item);
    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.page),
        color: AppColors.accentTint,
        child: const Icon(Icons.close, color: AppColors.accentInk),
      ),
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: _iconBox,
                  height: _iconBox,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    _icons[item.icon] ?? Icons.notifications_none,
                    size: 20,
                    color: ink,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!item.isRead) ...[
                            const _UnreadDot(),
                            const SizedBox(width: AppSpacing.xxs),
                          ],
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: item.isRead
                                  ? AppText.readableStrong.copyWith(
                                      fontWeight: FontWeight.w500,
                                    )
                                  : AppText.readableStrong,
                            ),
                          ),
                          if (item.count > 1) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            _CountBadge(count: item.count),
                          ],
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            RelativeTime.label(item.ts, DateTime.now()),
                            style: AppText.caption,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      FutureBuilder<String?>(
                        key: ValueKey('${item.id}@${item.ts}'),
                        future: readText(item),
                        builder: (context, snapshot) {
                          final done =
                              snapshot.connectionState == ConnectionState.done;
                          final text = item.isE2e
                              ? (done
                                    ? (snapshot.data ??
                                          NotificationTexts.encrypted)
                                    : '')
                              : item.message;
                          return Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.readable,
                          );
                        },
                      ),
                      if (destination.hasAction &&
                          (item.actionLabel ?? '').isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton.text(
                            label: item.actionLabel!,
                            tone: AppTextButtonTone.accent,
                            onPressed: onTap,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<FeedTileMenu>(
                  tooltip: NotificationTexts.menu,
                  icon: const Icon(
                    Icons.more_vert,
                    size: 20,
                    color: AppColors.muted,
                  ),
                  color: AppColors.background,
                  onSelected: onMenu,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: FeedTileMenu.toggleRead,
                      child: Text(
                        item.isRead
                            ? NotificationTexts.markUnread
                            : NotificationTexts.markRead,
                        style: AppText.body,
                      ),
                    ),
                    if (!item.isResolved)
                      const PopupMenuItem(
                        value: FeedTileMenu.resolve,
                        child: Text(
                          NotificationTexts.resolve,
                          style: AppText.body,
                        ),
                      ),
                    const PopupMenuItem(
                      value: FeedTileMenu.dismiss,
                      child: Text(
                        NotificationTexts.dismiss,
                        style: AppText.body,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) => Container(
    width: AppSpacing.navDot + 3,
    height: AppSpacing.navDot + 3,
    decoration: const BoxDecoration(
      color: AppColors.accent,
      shape: BoxShape.circle,
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    decoration: const BoxDecoration(
      color: AppColors.accentTint,
      borderRadius: AppRadius.pillAll,
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: AppText.caption.copyWith(color: AppColors.accentInk),
    ),
  );
}
