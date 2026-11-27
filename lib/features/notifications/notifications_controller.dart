import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/notifications/local_notification_service.dart';
import 'feed_actions.dart';
import 'models/feed_item.dart';
import 'models/feed_reducer.dart';
import 'notification_router.dart';
import 'notification_texts.dart';
import 'widgets/notifications_more_menu.dart';
import 'notifications_tour.dart';

class NotificationsController extends GetxController {
  NotificationsController({
    required this.feed,
    required this.router,
    required this.notifications,
    required this.connectivity,
    required this.conversations,
    this.tour,
  });

  final FeedRepository feed;
  final NotificationRouter router;
  final LocalNotificationService notifications;
  final ConnectivityService connectivity;
  final ConversationRepository conversations;

  /// The first-run tour; null where tours are not set up.
  final NotificationsTour? tour;

  /// The chips, in order: the priority each one asks the server for.
  static const priorities = ['all', 'high', 'medium', 'low', 'resolved'];
  static const chipLabels = [
    NotificationTexts.filterAll,
    NotificationTexts.filterHigh,
    NotificationTexts.filterMedium,
    NotificationTexts.filterLow,
    NotificationTexts.filterResolved,
  ];

  late final _actions = FeedActions(feed);

  /// The selected chips, by priority id. Never empty; user state, so no
  /// reload, reconnect or event touches it.
  final selectedIds = Rx<Set<String>>({'all'});
  final isUnreadOnly = false.obs;
  final isFilterLoading = false.obs;
  final isLoadingMore = false.obs;

  List<String> get _selection => [
    for (final p in priorities)
      if (selectedIds.value.contains(p)) p,
  ];

  /// The empty state's text: the filters when a chip other than All is on.
  String get emptyMessage {
    if (!selectedIds.value.contains('all')) {
      return NotificationTexts.emptyFilters;
    }
    return isUnreadOnly.value
        ? NotificationTexts.emptyUnread
        : NotificationTexts.emptyMessage;
  }

  List<FeedItem> get visible => FeedReducer.filterAny(
    feed.items,
    priorities: selectedIds.value,
    isUnreadOnly: isUnreadOnly.value,
    mutedConversations: {
      for (final c in conversations.conversations)
        if (c.isMuted) c.convId,
    },
  );

  bool get hasMore =>
      _selection.any((p) => feed.hasMore(p, isUnreadOnly.value));

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
    if (tour != null) {
      ever(feed.isLoading, (_) => _trigger?.schedule());
      ever(feed.hasError, (_) => _trigger?.schedule());
      ever(isFilterLoading, (_) => _trigger?.schedule());
      ever(feed.items, (_) => _trigger?.schedule());
    }
    if (feed.items.isEmpty) {
      fireAndLog('notifications_controller', () => feed.refresh());
    }
  }

  // ---- first-run tour ----------------------------------------------------------

  TourTrigger? _trigger;

  /// The screen was opened (the controller outlives it): a fresh try of the
  /// tour, so a tour that had to wait gets its turn on the next visit.
  void onScreenOpened() {
    if (tour == null) return;
    _trigger?.dispose();
    _trigger = TourTrigger(canTry: _canTryTour, start: _startTour)..schedule();
  }

  bool _canTryTour() {
    final state = viewState;
    return tour != null &&
        !isClosed &&
        Get.currentRoute == AppRoutes.notifications &&
        !isFilterLoading.value &&
        (state == AppViewState.content || state == AppViewState.empty);
  }

  Future<TourStart> _startTour() async {
    final tour = this.tour;
    if (tour == null || isClosed) return TourStart.failed;
    await WidgetsBinding.instance.endOfFrame;
    if (isClosed) return TourStart.failed;
    return tour.start();
  }

  Future<void> retry() async {
    await feed.refresh();
    await _ensure();
  }

  Future<void> onRefresh() async {
    await feed.refresh();
    await _ensure();
  }

  /// All is exclusive; the other chips add up. Deselecting the last one goes
  /// back to All.
  void toggleChip(String id) {
    selectedIds.value = AppPillBar.toggle(
      selectedIds.value,
      id,
      exclusiveId: 'all',
    );
    fireAndLog('notifications_controller', () => _ensure());
  }

  void setUnreadOnly(bool value) {
    isUnreadOnly.value = value;
    fireAndLog('notifications_controller', () => _ensure());
  }

  Future<void> _ensure() async {
    isFilterLoading.value = true;
    try {
      for (final p in _selection) {
        await feed.ensureFilter(p, isUnreadOnly.value);
      }
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
      for (final p in _selection) {
        await feed.loadMore(p, isUnreadOnly.value);
      }
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
    if (!item.isRead)
      fireAndLog('notifications_controller', () => setRead(item, isRead: true));
    if (destination.kind == DestinationKind.none) {
      router.showDetail(item);
    } else {
      router.handle(destination);
    }
  }

  Future<void> setRead(FeedItem item, {required bool isRead}) =>
      _actions.setRead(item, isRead: isRead);

  Future<void> resolve(FeedItem item) => _actions.resolve(item);

  Future<void> dismiss(FeedItem item) => _actions.dismiss(item);

  /// An item of the more menu: the two switches and the bulk actions.
  void onMenu(NotificationsMenuItem item) => switch (item) {
    NotificationsMenuItem.notifyGroups => setNotifyGroups(
      !notifications.shouldNotifyGroups.value,
    ),
    NotificationsMenuItem.unreadOnly => setUnreadOnly(!isUnreadOnly.value),
    NotificationsMenuItem.markAllRead => fireAndLog(
      'notifications_controller',
      () => markAllRead(),
    ),
    NotificationsMenuItem.markAllResolved => fireAndLog(
      'notifications_controller',
      () => resolveAll(),
    ),
    NotificationsMenuItem.clearResolved => fireAndLog(
      'notifications_controller',
      () => clearResolved(),
    ),
  };

  Future<void> markAllRead() => _actions.run(feed.markAllRead);

  Future<void> resolveAll() => _actions.run(feed.resolveAll);

  Future<void> clearResolved() => _actions.run(feed.clearResolved);

  void setNotifyGroups(bool value) => fireAndLog(
    'notifications_controller',
    () => notifications.setNotifyGroups(value),
  );

  Future<void> onPermissionAction() async {
    if (notifications.wasAsked.value) {
      await AppSettings.open();
    } else {
      await notifications.request();
    }
  }

  void _say(SocketCallError e) {
    AppNotices.error(
      e.message.isNotEmpty ? e.message : NotificationTexts.actionFailed,
    );
  }
}
