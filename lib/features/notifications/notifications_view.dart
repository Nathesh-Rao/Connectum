import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_filter_chips.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import 'notification_texts.dart';
import 'notifications_controller.dart';
import 'widgets/feed_tile.dart';

enum _HeaderMenu { markAllRead, markAllResolved, clearResolved }

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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Obx(
              () => AppFilterChips(
                chips: [
                  for (
                    var i = 0;
                    i < NotificationsController.chipLabels.length;
                    i++
                  )
                    AppFilterChip(
                      label: NotificationsController.chipLabels[i],
                      count: i == 0
                          ? 0
                          : c.feed.counts.value.forPriority(
                              NotificationsController.priorities[i],
                            ),
                    ),
                ],
                selected: c.selected.value,
                onSelected: c.selectChip,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    NotificationTexts.notifyGroups,
                    style: AppText.readable,
                  ),
                ),
                Obx(
                  () => Switch(
                    value: c.notifications.shouldNotifyGroups.value,
                    activeThumbColor: AppColors.accent,
                    onChanged: c.setNotifyGroups,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    NotificationTexts.unreadOnly,
                    style: AppText.readable,
                  ),
                ),
                Obx(
                  () => Switch(
                    value: c.isUnreadOnly.value,
                    activeThumbColor: AppColors.accent,
                    onChanged: c.setUnreadOnly,
                  ),
                ),
              ],
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
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xxs,
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
          PopupMenuButton<_HeaderMenu>(
            tooltip: NotificationTexts.menu,
            icon: const Icon(Icons.more_horiz, color: AppColors.ink),
            color: AppColors.background,
            onSelected: (m) => switch (m) {
              _HeaderMenu.markAllRead => c.markAllRead(),
              _HeaderMenu.markAllResolved => c.resolveAll(),
              _HeaderMenu.clearResolved => c.clearResolved(),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HeaderMenu.markAllRead,
                child: Text(NotificationTexts.markAllRead, style: AppText.body),
              ),
              PopupMenuItem(
                value: _HeaderMenu.markAllResolved,
                child: Text(
                  NotificationTexts.markAllResolved,
                  style: AppText.body,
                ),
              ),
              PopupMenuItem(
                value: _HeaderMenu.clearResolved,
                child: Text(
                  NotificationTexts.clearResolved,
                  style: AppText.body,
                ),
              ),
            ],
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
        emptyMessage: c.isUnreadOnly.value
            ? NotificationTexts.emptyUnread
            : NotificationTexts.emptyMessage,
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
              SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (context, i) => const Divider(
                  height: 1,
                  color: AppColors.line,
                  indent: AppSpacing.page,
                  endIndent: AppSpacing.page,
                ),
                itemBuilder: (context, i) {
                  final item = items[i];
                  return FeedTile(
                    key: ValueKey(item.id),
                    item: item,
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
                          child: Center(child: AppSpinner.medium()),
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
