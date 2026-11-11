import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_pill_bar.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import 'notification_texts.dart';
import 'notifications_controller.dart';
import 'widgets/feed_tile.dart';
import 'widgets/notifications_more_menu.dart';

// TUNE ME: notifications spacing (dp). Hot restart after changing a value.
class NotificationsSpacing {
  NotificationsSpacing._();

  /// Title row bottom to the pills' top.
  static const double titleToPills = 16;

  /// Pills' bottom to the first tile's content (icon circle / title). Change
  /// this alone to move the first tile; the list top padding follows.
  static const double pillsToFirstTile = 32;

  /// Horizontal gap between the pills.
  static const double pillGap = 10;

  /// A tile's own space above its content. Counted inside pillsToFirstTile,
  /// so changing it does not move the first tile.
  static const double firstTileTopPadding = 12;

  /// Blank space at the top of the scrolling list, above the first tile's own
  /// padding. Scrolls away with the list.
  static const double listTopPadding = pillsToFirstTile - firstTileTopPadding;
}

class NotificationsView extends GetView<NotificationsController> {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
    ]);
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          _Header(controller: c),
          const AppOfflineBar(),
          Obx(
            () => c.isPermissionRowShown
                ? _PermissionRow(controller: c)
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              NotificationsSpacing.titleToPills,
              AppSpacing.page,
              0,
            ),
            child: Obx(
              () => AppPillBar.multi(
                size: AppPillSize.compact,
                gap: NotificationsSpacing.pillGap,
                pills: [
                  for (
                    var i = 0;
                    i < NotificationsController.chipLabels.length;
                    i++
                  )
                    AppPill(
                      id: NotificationsController.priorities[i],
                      label: NotificationsController.chipLabels[i],
                      count: i == 0
                          ? 0
                          : c.feed.counts.value.forPriority(
                              NotificationsController.priorities[i],
                            ),
                    ),
                ],
                selectedIds: c.selectedIds.value,
                onToggle: c.toggleChip,
                exclusiveId: 'all',
              ),
            ),
          ),
          Expanded(child: _Body(controller: c)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
        0,
      ),
      child: Row(
        children: [
          AppButton.icon(
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: Get.back,
          ),
          const Expanded(
            child: Text(NotificationTexts.screenTitle, style: AppText.title),
          ),
          NotificationsMoreMenu(
            shouldNotifyGroups: c.notifications.shouldNotifyGroups,
            isUnreadOnly: c.isUnreadOnly,
            onSelected: c.onMenu,
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 18,
            color: AppColors.muted,
          ),
          const SizedBox(width: AppSpacing.xs),
          const Expanded(
            child: Text(
              NotificationTexts.permissionOffRow,
              style: AppText.readable,
            ),
          ),
          Obx(
            () => AppButton.text(
              label: c.permissionAction,
              tone: AppTextButtonTone.accent,
              onPressed: c.onPermissionAction,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final NotificationsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final items = c.visible;
      final state = c.viewState;
      return AppStateView(
        state: state,
        emptyImage: AppStateImageKind.emptyGeneric,
        emptyTitle: NotificationTexts.emptyTitle,
        emptyMessage: c.emptyMessage,
        errorMessage: NotificationTexts.errorMessage,
        onRetry: c.retry,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 300) c.loadMore();
            return false;
          },
          child: AppRefresh(
            onRefresh: c.onRefresh,
            slivers: [
              const SliverToBoxAdapter(
                child: SizedBox(height: NotificationsSpacing.listTopPadding),
              ),
              SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (context, i) => const Divider(
                  height: 1,
                  color: AppColors.line,
                  indent:
                      AppSpacing.page +
                      AppSpacing.feedIconCircle +
                      AppSpacing.sm,
                  endIndent: AppSpacing.page,
                ),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return FeedTile(
                    key: ValueKey(item.id),
                    item: item,
                    topPadding: NotificationsSpacing.firstTileTopPadding,
                    readText: c.feed.readableText,
                    onTap: () => c.open(item),
                    onDismissed: () => c.dismiss(item),
                    onMenu: (m) => switch (m) {
                      FeedTileMenu.toggleRead => c.setRead(
                        item,
                        isRead: !item.isRead,
                      ),
                      FeedTileMenu.resolve => c.resolve(item),
                      FeedTileMenu.dismiss => c.dismiss(item),
                    },
                  );
                },
              ),
              SliverToBoxAdapter(
                child: Obx(
                  () => c.isLoadingMore.value
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Center(child: AppSpinner()),
                        )
                      : const SizedBox(height: AppSpacing.xl),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
