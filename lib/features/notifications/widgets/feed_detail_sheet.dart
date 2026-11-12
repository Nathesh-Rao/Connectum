import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_pill_bar.dart';
import '../../../data/repositories/feed_repository.dart';
import '../feed_actions.dart';
import '../feed_highlight.dart';
import '../models/feed_item.dart';
import '../notification_style.dart';
import '../notification_texts.dart';

/// The whole of one item, with the actions of the tile menu: the way to where
/// it leads first (when it leads somewhere), then read, resolve and dismiss.
class FeedDetailSheet extends StatelessWidget {
  const FeedDetailSheet({
    super.key,
    required this.item,
    required this.text,
    required this.feed,
    required this.actions,
    this.onOpen,
  });

  final FeedItem item;

  /// The message to show; for an end-to-end item the opened text.
  final Future<String?> text;

  /// Read for the live state of the item (read, resolved, gone).
  final FeedRepository feed;
  final FeedActions actions;

  /// Where the item leads; null when it leads nowhere else.
  final VoidCallback? onOpen;

  static Future<void> show(
    BuildContext context,
    FeedItem item, {
    required Future<String?> text,
    required FeedRepository feed,
    required FeedActions actions,
    VoidCallback? onOpen,
  }) => AppBottomSheet.show<void>(
    context,
    title: '',
    hasHeader: false,
    child: FeedDetailSheet(
      item: item,
      text: text,
      feed: feed,
      actions: actions,
      onOpen: onOpen,
    ),
  );

  FeedItem get _live =>
      feed.items.firstWhereOrNull((i) => i.id == item.id) ?? item;

  /// Label and value pairs worth showing; empty values are left out.
  List<(String, String)> get _details {
    return [
      if (FeedHighlight.deviceLabel(item) case final device?)
        (NotificationTexts.detailDevice, device),
      if (item.source case final source? when source.isNotEmpty)
        (NotificationTexts.detailSource, source),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FeedSheetHeader(item: item),
        const SizedBox(height: AppSpacing.md),
        Text(
          item.title.isEmpty ? NotificationTexts.screenTitle : item.title,
          style: AppText.title.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        FutureBuilder<String?>(
          future: text,
          builder: (context, snapshot) {
            final body = snapshot.connectionState == ConnectionState.done
                ? (snapshot.data ?? NotificationTexts.encrypted)
                : '';
            return Text.rich(
              TextSpan(
                style: AppText.body,
                children: FeedHighlight.spans(body, item, base: AppText.body),
              ),
            );
          },
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _Details(rows: details),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Actions(
          item: item,
          actions: actions,
          onOpen: onOpen,
          liveItem: () => _live,
        ),
      ],
    );
  }
}

/// The leading circle, the category pill, the priority pill and the time;
/// the pills wrap onto a second line on a narrow screen.
class FeedSheetHeader extends StatelessWidget {
  const FeedSheetHeader({super.key, required this.item});

  final FeedItem item;

  static (String, AppPillKind) _priority(String priority) => switch (priority) {
    'high' => (NotificationTexts.priorityHigh, AppPillKind.accent),
    'medium' => (NotificationTexts.priorityMedium, AppPillKind.violet),
    'resolved' => (NotificationTexts.priorityResolved, AppPillKind.success),
    _ => (NotificationTexts.priorityLow, AppPillKind.calm),
  };

  @override
  Widget build(BuildContext context) {
    final style = styleFor(item);
    final (label, kind) = _priority(item.priority);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          decoration: BoxDecoration(color: style.tint, shape: BoxShape.circle),
          child: Icon(style.icon, size: 22, color: style.color),
        ),
        _CategoryPill(style: style),
        _PriorityChip(label: label, kind: kind),
        if (item.ts > 0)
          Text(
            RelativeTime.label(item.ts, DateTime.now()),
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
      ],
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.style});

  final NotificationStyle style;

  @override
  Widget build(BuildContext context) => Container(
    height: AppSpacing.categoryPillHeight,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    decoration: BoxDecoration(
      color: style.tint,
      borderRadius: AppRadius.pillAll,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          style.category,
          style: AppText.pillCompact.copyWith(color: style.strong),
        ),
      ],
    ),
  );
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.label, required this.kind});

  final String label;
  final AppPillKind kind;

  @override
  Widget build(BuildContext context) => Container(
    height: AppSpacing.priorityPillHeight,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    decoration: BoxDecoration(
      color: kind.tint,
      borderRadius: AppRadius.pillAll,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppText.label.copyWith(color: kind.ink, height: 1)),
      ],
    ),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.mdAll,
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Row(
              children: [
                Text(
                  label,
                  style: AppText.readable.copyWith(color: AppColors.muted),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.readableStrong,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.actions,
    required this.onOpen,
    required this.liveItem,
  });

  final FeedItem item;
  final FeedActions actions;
  final VoidCallback? onOpen;
  final FeedItem Function() liveItem;

  Future<void> _closeAfter(BuildContext context, Future<bool> action) async {
    final navigator = Navigator.of(context);
    if (await action && navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    return Obx(() {
      final live = liveItem();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (open != null) ...[
            AppButton.primary(
              label: (item.actionLabel ?? '').isEmpty
                  ? NotificationTexts.open
                  : item.actionLabel!,
              isCentered: true,
              onPressed: () {
                Navigator.of(context).pop();
                if (!live.isRead) {
                  actions.setRead(live, isRead: true);
                }
                open();
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: _ActionPill(
                  icon: live.isRead
                      ? Icons.mark_email_unread_outlined
                      : Icons.done_all,
                  label: live.isRead
                      ? NotificationTexts.markUnread
                      : NotificationTexts.markRead,
                  onTap: () => actions.setRead(live, isRead: !live.isRead),
                ),
              ),
              if (!live.isResolved) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _ActionPill(
                    icon: Icons.check_circle_outline,
                    label: NotificationTexts.resolve,
                    onTap: () => _closeAfter(context, actions.resolve(live)),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _ActionPill(
                  icon: Icons.close,
                  label: NotificationTexts.dismiss,
                  isDestructive: true,
                  onTap: () => _closeAfter(context, actions.dismiss(live)),
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final ink = isDestructive ? AppColors.error : AppColors.ink;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AppSpacing.minTapTarget,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: isDestructive ? AppColors.primarySoft : AppColors.fill,
            borderRadius: AppRadius.pillAll,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: ink),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.readableStrong.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
