import 'dart:async';

import 'package:get/get.dart';

import '../../core/utils/app_settings.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/notifications/local_notification_service.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'models/feed_item.dart';
import 'models/feed_reducer.dart';
import 'notification_router.dart';
import 'notification_texts.dart';

class NotificationsController extends GetxController {
  NotificationsController({
    required this.feed,
    required this.router,
    required this.notifications,
    required this.connectivity,
    required this.conversations,
  });

  final FeedRepository feed;
  final NotificationRouter router;
  final LocalNotificationService notifications;
  final ConnectivityService connectivity;
  final ConversationRepository conversations;

  /// The chips, in order: the priority each one asks the server for.
  static const priorities = ['all', 'high', 'medium', 'low', 'resolved'];
  static const chipLabels = [
    NotificationTexts.filterAll,
    NotificationTexts.filterHigh,
    NotificationTexts.filterMedium,
    NotificationTexts.filterLow,
    NotificationTexts.filterResolved,
  ];

  final selected = 0.obs;
  final isUnreadOnly = false.obs;
  final isFilterLoading = false.obs;
  final isLoadingMore = false.obs;

  String get priority => priorities[selected.value];

  List<FeedItem> get visible => FeedReducer.filter(
    feed.items,
    priority: priority,
    isUnreadOnly: isUnreadOnly.value,
    mutedConversations: {
      for (final c in conversations.conversations)
        if (c.isMuted) c.convId,
    },
  );

  bool get hasMore => feed.hasMore(priority, isUnreadOnly.value);

  AppViewState get viewState {
    if (feed.isLoading.value && feed.items.isEmpty) {
      return AppViewState.loading;
    }
    if (isFilterLoading.value && visible.isEmpty) return AppViewState.loading;
    if (feed.hasError.value && feed.items.isEmpty) {
      return connectivity.state.value == AppConnectivity.online
          ? AppViewState.error
          : AppViewState.offline;
    }
    return visible.isEmpty ? AppViewState.empty : AppViewState.content;
  }

  /// Shows the way to the system settings when notifications are off.
  bool get isPermissionRowShown => !notifications.isEnabled.value;

  String get permissionAction => notifications.wasAsked.value
      ? NotificationTexts.permissionOpenSettings
      : NotificationTexts.permissionTurnOn;

  @override
  void onInit() {
    super.onInit();
    if (feed.items.isEmpty) {
      unawaited(feed.refresh());
    }
  }

  Future<void> retry() async {
    await feed.refresh();
    await _ensure();
  }

  Future<void> onRefresh() async {
    await feed.refresh();
    await _ensure();
  }

  void selectChip(int index) {
    if (index == selected.value) return;
    selected.value = index;
    unawaited(_ensure());
  }

  void setUnreadOnly(bool value) {
    isUnreadOnly.value = value;
    unawaited(_ensure());
  }

  Future<void> _ensure() async {
    isFilterLoading.value = true;
    try {
      await feed.ensureFilter(priority, isUnreadOnly.value);
    } on SocketCallError catch (e) {
      _say(e);
    } finally {
      isFilterLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore) return;
    isLoadingMore.value = true;
    try {
      await feed.loadMore(priority, isUnreadOnly.value);
    } on SocketCallError catch (e) {
      _say(e);
    } finally {
      isLoadingMore.value = false;
    }
  }

  // ---- items ---------------------------------------------------------------

  /// Tap on a tile: read, then where it leads. An item that leads nowhere
  /// shows its detail.
  Future<void> open(FeedItem item) async {
    final destination = NotificationRouter.resolve(item);
    if (!item.isRead) unawaited(setRead(item, isRead: true));
    if (destination.kind == DestinationKind.none) {
      router.showDetail(item);
    } else {
      router.handle(destination);
    }
  }

  Future<void> setRead(FeedItem item, {required bool isRead}) =>
      _run(() => feed.setRead([item.id], isRead: isRead));

  Future<void> resolve(FeedItem item) => _run(() => feed.resolve(item.id));

  Future<void> dismiss(FeedItem item) => _run(() => feed.dismiss(item.id));

  Future<void> markAllRead() => _run(feed.markAllRead);

  Future<void> resolveAll() => _run(feed.resolveAll);

  Future<void> clearResolved() => _run(feed.clearResolved);

  void setNotifyGroups(bool value) =>
      unawaited(notifications.setNotifyGroups(value));

  Future<void> onPermissionAction() async {
    if (notifications.wasAsked.value) {
      await AppSettings.open();
    } else {
      await notifications.request();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on SocketCallError catch (e) {
      _say(e);
      if (e.code == 'not_found') feed.scheduleRefresh();
    }
  }

  void _say(SocketCallError e) {
    AppNotices.error(
      e.message.isNotEmpty ? e.message : NotificationTexts.actionFailed,
    );
  }
}
