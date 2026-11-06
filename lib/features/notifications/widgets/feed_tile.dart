import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/app_button.dart';
import '../models/feed_item.dart';
import '../notification_router.dart';
import '../notification_style.dart';
import '../notification_texts.dart';
import 'feed_priority_pill.dart';

enum FeedTileMenu { toggleRead, resolve, dismiss }

/// One feed item: a round icon from [styleFor], title, clipped message, time,
/// the priority pill, a count when the server folded several into one, an
/// unread dot, the more menu and an optional action button.
class FeedTile extends StatelessWidget {
  const FeedTile({
    super.key,
    required this.item,
    required this.readText,
    required this.onTap,
    required this.onMenu,
    required this.onDismissed,
    this.topPadding = AppSpacing.sm,
  });

  final FeedItem item;

  /// The words to show: the message, or for an end-to-end item the opened
  /// text (null while it cannot be read).
  final Future<String?> Function(FeedItem item) readText;
  final VoidCallback onTap;
  final ValueChanged<FeedTileMenu> onMenu;
  final VoidCallback onDismissed;

  /// Space above the tile's content (icon circle / title).
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final style = styleFor(item);
    final destination = NotificationRouter.resolve(item);
    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: FeedSwipeBackground(style: style),
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.page,
              right: AppSpacing.xxs,
              top: topPadding,
              bottom: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: item.isRead ? 0.75 : 1,
                  child: Container(
                    width: AppSpacing.feedIconCircle,
                    height: AppSpacing.feedIconCircle,
                    decoration: BoxDecoration(
                      color: style.tint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      style.icon,
                      size: AppSpacing.feedIcon,
                      color: style.color,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!item.isRead) ...[
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xxs,
                              ),
                              child: _UnreadDot(color: style.color),
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                          ],
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: item.isRead
                                  ? AppText.readableStrong.copyWith(
                                      fontWeight: FontWeight.w500,
                                    )
                                  : AppText.readableStrong,
                            ),
                          ),
                        ],
                      ),
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
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.readable,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            RelativeTime.label(item.ts, DateTime.now()),
                            style: AppText.caption,
                          ),
                          FeedPriorityPill(priority: item.priority),
                          if (item.count > 1) _CountBadge(count: item.count),
                        ],
                      ),
                      if (destination.hasAction &&
                          (item.actionLabel ?? '').isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton.text(
                            label: item.actionLabel!,
                            color: style.color,
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

/// What the swipe reveals: the tile's tint, a little stronger, with the
/// dismiss label and icon in its strong shade.
class FeedSwipeBackground extends StatelessWidget {
  const FeedSwipeBackground({super.key, required this.style});

  final NotificationStyle style;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: AppSpacing.page),
    color: style.tintStrong,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          NotificationTexts.dismiss,
          style: AppText.readableStrong.copyWith(color: style.strong),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Icon(Icons.close, color: style.strong),
      ],
    ),
  );
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: AppSpacing.navDot + 3,
    height: AppSpacing.navDot + 3,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
