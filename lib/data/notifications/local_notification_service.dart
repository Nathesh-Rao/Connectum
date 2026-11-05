import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_notices.dart';
import '../../features/notifications/models/feed_item.dart';
import '../../features/notifications/notification_router.dart';
import '../../features/notifications/notification_texts.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/feed_repository.dart';
import '../session_store.dart';
import 'local_notification_rules.dart';
import 'push/push_payload.dart';
import 'push/push_token_registry.dart';

/// System notifications for live feed items while the app is in the
/// background, and the light in-app notice while it is on screen. No push:
/// a killed app cannot be woken. The tap goes to [NotificationRouter].
class LocalNotificationService extends GetxService with WidgetsBindingObserver {
  LocalNotificationService(
    this._feed,
    this._conversations,
    this._store,
    this._router,
    this._registry,
  );

  final FeedRepository _feed;
  final ConversationRepository _conversations;
  final SessionStore _store;
  final NotificationRouter _router;
  final PushTokenRegistry _registry;

  static const _askedKey = 'notif.asked';
  static const _groupsKey = 'notif.groups';
  static const _summaryMin = 3;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _subscriptions = <StreamSubscription<dynamic>>[];

  /// Notifications are allowed on this phone right now.
  final isEnabled = true.obs;

  /// The person was asked (or said "not now"): the notifications screen then
  /// shows the way to the system settings, and nothing asks again.
  final wasAsked = false.obs;

  /// "Notify for group messages": per signed-in person, on by default.
  final shouldNotifyGroups = true.obs;

  bool _isReady = false;
  bool _isForeground = true;

  /// Debug page only: behave as if the app were in the background.
  bool debugForceBackground = false;

  bool get isForeground => _isForeground && !debugForceBackground;

  static const _importances = {
    'messages': Importance.defaultImportance,
    'approvals': Importance.high,
    'tasks': Importance.defaultImportance,
    'system': Importance.low,
    'security': Importance.high,
  };

  Future<LocalNotificationService> start() async {
    _isForeground =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _onTap(r.payload),
      );
      await _createChannels();
      _isReady = true;
    } catch (e) {
      debugPrint('Local notifications unavailable: ${e.runtimeType}');
      return this;
    }
    wasAsked.value = await _store.readValue(_askedKey) != null;
    await refreshPermission();
    _subscriptions
      ..add(_feed.onItem.listen(_onItem))
      ..add(_feed.onGone.listen(_cancelAll))
      ..add(_feed.onNotice.listen(_onNotice));
    await _loadGroups();
    ever(_store.current, (_) {
      unawaited(_plugin.cancelAll());
      unawaited(_loadGroups());
    });
    ever(_feed.items, (_) => _sweepRead());
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _onTap(launch?.notificationResponse?.payload);
    }
    return this;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) unawaited(refreshPermission());
  }

  // ---- permission ----------------------------------------------------------

  Future<void> refreshPermission() async {
    if (!_isReady) return;
    isEnabled.value = await _check();
    await _registry.setPermitted(isEnabled.value);
  }

  Future<bool> _check() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// First Home after sign-in, never asked: the explainer comes first (the
  /// caller shows it), and only an "Allow" reaches the system prompt.
  bool get shouldExplain => _isReady && !wasAsked.value && !isEnabled.value;

  /// The system prompt. The answer is remembered, so nothing asks twice.
  Future<bool> request() async {
    if (!_isReady) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
    await markAsked();
    await refreshPermission();
    return isEnabled.value;
  }

  Future<void> markAsked() async {
    wasAsked.value = true;
    await _store.writeValue(_askedKey, 'asked');
  }

  String? get _groupsStoreKey {
    final org = _store.orgId;
    final user = _store.userId;
    return org == null || user == null ? null : '$_groupsKey.$org.$user';
  }

  Future<void> _loadGroups() async {
    final key = _groupsStoreKey;
    shouldNotifyGroups.value =
        key == null || await _store.readValue(key) != 'off';
  }

  Future<void> setNotifyGroups(bool value) async {
    shouldNotifyGroups.value = value;
    final key = _groupsStoreKey;
    if (key != null) await _store.writeValue(key, value ? 'on' : 'off');
  }

  // ---- channels ------------------------------------------------------------

  Future<void> _createChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final e in NotificationTexts.channels.entries) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          e.key,
          e.value.$1,
          description: e.value.$2,
          importance: _importances[e.key] ?? Importance.defaultImportance,
        ),
      );
    }
  }

  // ---- incoming items ------------------------------------------------------

  String? get _openConversation {
    const prefix = '/conversation/';
    final route = Get.currentRoute;
    if (!route.startsWith(prefix)) return null;
    return Uri.decodeComponent(route.substring(prefix.length));
  }

  NotificationShow _decide(FeedItem item) => LocalNotificationRules.decide(
    item,
    isForeground: isForeground,
    myUser: _store.userId,
    mutedConversations: {
      for (final c in _conversations.conversations)
        if (c.isMuted) c.convId,
    },
    openConversationId: _openConversation,
    shouldNotifyGroups: shouldNotifyGroups.value,
  );

  Future<void> _onItem(FeedItem item) async {
    switch (_decide(item)) {
      case NotificationShow.none:
        return;
      case NotificationShow.system:
        if (isEnabled.value) await show(item);
      case NotificationShow.inApp:
        await _showInApp(item);
    }
  }

  void _onNotice(FeedNotice notice) {
    if (!isForeground) return;
    final ticketId = notice.ticketId;
    if (ticketId != null) {
      AppNotices.show(
        notice.line,
        actionLabel: 'Open',
        onAction: () =>
            _router.handle(Destination.ticket('$ticketId', notice.tstruct)),
      );
      return;
    }
    final taskId = notice.taskId;
    if (taskId == null) {
      AppNotices.info(notice.line);
      return;
    }
    AppNotices.show(
      notice.line,
      actionLabel: 'Open',
      onAction: () => _router.handle(Destination.task(taskId)),
    );
  }

  Future<void> _showInApp(FeedItem item) async {
    final text = await _feed.readableText(item);
    final body = item.isE2e
        ? (text ?? NotificationTexts.newMessage)
        : item.message;
    final destination = NotificationRouter.resolve(item);
    AppNotices.show(
      FeedItem.clip(body, LocalNotificationRules.bodyMax),
      title: item.isE2e && text == null ? null : item.title,
      key: 'feed-${item.id}',
      actionLabel: destination.hasAction ? (item.actionLabel ?? 'Open') : null,
      onAction: destination.hasAction ? () => _openItem(item) : null,
    );
  }

  /// Shows (or replaces) the system notification of [item]. The id comes
  /// from the item, so a coalesced item never stacks.
  Future<void> show(FeedItem item) async {
    if (!_isReady) return;
    final text = await _feed.readableText(item);
    final String title;
    final String? body;
    if (item.isE2e) {
      final isOpen = text != null;
      title = isOpen && item.title.isNotEmpty
          ? item.title
          : NotificationTexts.newMessage;
      body = isOpen
          ? FeedItem.clip(text, LocalNotificationRules.bodyMax)
          : null;
    } else {
      title = item.title.isEmpty ? NotificationTexts.newMessage : item.title;
      body = item.message.isEmpty
          ? null
          : FeedItem.clip(item.message, LocalNotificationRules.bodyMax);
    }
    final channel = LocalNotificationRules.channelOf(item);
    final info = NotificationTexts.channels[channel]!;
    final payload = PushPayload(
      itemId: item.id,
      actionType: item.actionType,
      chatId: item.chatId,
      messageId: item.messageId,
      count: item.count,
    ).toJson();
    try {
      await _plugin.show(
        id: LocalNotificationRules.notificationId(item.id),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            info.$1,
            channelDescription: info.$2,
            importance: _importances[channel] ?? Importance.defaultImportance,
            priority: switch (item.priority) {
              'high' => Priority.high,
              'low' => Priority.low,
              _ => Priority.defaultPriority,
            },
            groupKey: _groupKey(channel),
            number: item.count > 1 ? item.count : null,
            styleInformation: body == null
                ? null
                : BigTextStyleInformation(body),
          ),
          iOS: DarwinNotificationDetails(
            threadIdentifier: channel,
            badgeNumber: _feed.unread.value,
          ),
        ),
        payload: payload,
      );
      await _updateSummary(channel);
    } catch (e) {
      debugPrint('Local notification failed: ${e.runtimeType}');
    }
  }

  // ---- group summary -------------------------------------------------------

  static String _groupKey(String channel) => 'cn.$channel';

  static int _summaryId(String channel) =>
      LocalNotificationRules.notificationId('summary:$channel');

  Future<void> _updateSummary(String channel) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    final active = await android.getActiveNotifications();
    final summaryId = _summaryId(channel);
    final shown = active
        .where((n) => n.groupKey?.endsWith(_groupKey(channel)) ?? false)
        .where((n) => n.id != summaryId)
        .length;
    if (shown >= _summaryMin) {
      final info = NotificationTexts.channels[channel]!;
      await _plugin.show(
        id: summaryId,
        title: info.$1,
        body: '$shown new',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            info.$1,
            channelDescription: info.$2,
            groupKey: _groupKey(channel),
            setAsGroupSummary: true,
          ),
        ),
      );
    } else {
      await _plugin.cancel(id: summaryId);
    }
  }

  // ---- clearing ------------------------------------------------------------

  Future<void> _cancelAll(List<String> ids) async {
    if (!_isReady) return;
    for (final id in ids) {
      await _plugin.cancel(id: LocalNotificationRules.notificationId(id));
    }
    for (final channel in NotificationTexts.channels.keys) {
      await _updateSummary(channel);
    }
  }

  /// After a re-read: items read or resolved elsewhere lose their banner.
  Future<void> _sweepRead() async {
    if (!_isReady) return;
    final done = [
      for (final i in _feed.items)
        if (i.isRead || i.isResolved) i.id,
    ];
    if (done.isEmpty) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    final active = {
      for (final n in await android.getActiveNotifications()) n.id,
    };
    final stale = [
      for (final id in done)
        if (active.contains(LocalNotificationRules.notificationId(id))) id,
    ];
    if (stale.isNotEmpty) await _cancelAll(stale);
  }

  // ---- taps ----------------------------------------------------------------

  void _onTap(String? raw) {
    final payload = PushPayload.tryParse(raw);
    if (payload == null) return;
    _router.handlePayload(payload);
    final id = payload.itemId;
    if (id != null) {
      unawaited(_feed.setRead([id], isRead: true).catchError((_) {}));
    }
  }

  void _openItem(FeedItem item) {
    _router.handleItem(item);
    unawaited(_feed.setRead([item.id], isRead: true).catchError((_) {}));
  }
}
