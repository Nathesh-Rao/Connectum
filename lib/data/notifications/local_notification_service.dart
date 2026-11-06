import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import '../../features/notifications/models/feed_item.dart';
import '../../features/notifications/notification_router.dart';
import '../../features/notifications/notification_texts.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/feed_repository.dart';
import '../session_store.dart';
import 'local_notification_rules.dart';
import 'push/push_payload.dart';
import 'push/push_token_registry.dart';

/// System notifications for live feed items, in the foreground and the
/// background alike: the `feed_item` event is the single trigger. No push: a
/// killed app cannot be woken. The tap goes to [NotificationRouter].
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

  /// Item id -> the `ts|count` last shown, so one event never shows twice
  /// while a coalesced item (a higher count) still does.
  final _shown = <String, String>{};

  static const _importances = {
    'messages': Importance.high,
    'approvals': Importance.high,
    'tasks': Importance.defaultImportance,
    'system': Importance.defaultImportance,
    'security': Importance.high,
  };

  /// Channel settings cannot change after creation, so a changed setting needs
  /// a new id; the earlier ones are deleted at startup.
  static const _channelSuffix = '_v2';
  static const _smallIcon = 'ic_stat_notification';

  static String channelId(String channel) => '$channel$_channelSuffix';

  static void _log(String line) => debugPrint('notifyflow: $line');

  Future<LocalNotificationService> start() async {
    WidgetsBinding.instance.addObserver(this);
    _log('start lifecycle=${WidgetsBinding.instance.lifecycleState}');
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_smallIcon),
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
      _log('plugin initialised, small icon=$_smallIcon');
    } catch (e) {
      _log('initialise failed: $e');
      return this;
    }
    wasAsked.value = await _store.readValue(_askedKey) != null;
    await refreshPermission();
    _subscriptions
      ..add(_feed.onItem.listen(_onItem))
      ..add(_feed.onGone.listen(_cancelAll));
    await _loadGroups();
    ever(_store.current, (_) {
      _shown.clear();
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
    _log('lifecycle=$state');
    if (state == AppLifecycleState.resumed) unawaited(refreshPermission());
  }

  // ---- permission ----------------------------------------------------------

  Future<void> refreshPermission() async {
    if (!_isReady) return;
    isEnabled.value = await _check();
    _log('permission enabled=${isEnabled.value}');
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
    for (final base in NotificationTexts.channels.keys) {
      await android.deleteNotificationChannel(channelId: base);
    }
    for (final e in NotificationTexts.channels.entries) {
      final importance = _importances[e.key] ?? Importance.defaultImportance;
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          channelId(e.key),
          e.value.$1,
          description: e.value.$2,
          importance: importance,
          playSound: true,
          enableVibration: true,
        ),
      );
      _log('channel ${channelId(e.key)} created importance=${importance.name}');
    }
  }

  // ---- incoming items ------------------------------------------------------

  String? get _openConversation {
    const prefix = '/conversation/';
    final route = Get.currentRoute;
    if (!route.startsWith(prefix)) return null;
    return Uri.decodeComponent(route.substring(prefix.length));
  }

  NotificationDecision _decide(FeedItem item) => LocalNotificationRules.explain(
    item,
    myUser: _store.userId,
    mutedConversations: {
      for (final c in _conversations.conversations)
        if (c.isMuted) c.convId,
    },
    openConversationId: _openConversation,
    shouldNotifyGroups: shouldNotifyGroups.value,
  );

  Future<void> _onItem(FeedItem item) async {
    _log(
      'feed_item id=${item.id} priority=${item.priority} '
      'category=${item.category} actionType=${item.actionType} '
      'chatId=${item.chatId}',
    );
    final decision = _decide(item);
    if (decision.show == NotificationShow.none) {
      _log('decision id=${item.id} ${decision.reason}');
      return;
    }
    final signature = '${item.ts}|${item.count}';
    if (_shown[item.id] == signature) {
      _log('decision id=${item.id} skipped: already shown');
      return;
    }
    isEnabled.value = await _check();
    _log('permission enabled=${isEnabled.value}');
    if (!isEnabled.value) {
      _log('decision id=${item.id} skipped: permission off');
      return;
    }
    _log('decision id=${item.id} ${decision.reason}');
    _shown[item.id] = signature;
    await show(item);
  }

  /// Shows (or replaces) the system notification of [item]; false when it
  /// could not be posted. The id comes from the item, so a coalesced item
  /// never stacks.
  Future<bool> show(FeedItem item) async {
    if (!_isReady) {
      _log('show id=${item.id} skipped: plugin not ready');
      return false;
    }
    final channel = LocalNotificationRules.channelOf(item);
    final info = NotificationTexts.channels[channel]!;
    final importance = _importances[channel] ?? Importance.defaultImportance;
    try {
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
      final payload = PushPayload(
        itemId: item.id,
        actionType: item.actionType,
        chatId: item.chatId,
        messageId: item.messageId,
        count: item.count,
      ).toJson();
      _log('show id=${item.id} channel=${channelId(channel)} calling');
      await _plugin.show(
        id: LocalNotificationRules.notificationId(item.id),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId(channel),
            info.$1,
            channelDescription: info.$2,
            importance: importance,
            priority: importance == Importance.high
                ? Priority.high
                : Priority.defaultPriority,
            playSound: true,
            enableVibration: true,
            silent: false,
            icon: _smallIcon,
            groupKey: _groupKey(channel),
            number: item.count > 1 ? item.count : null,
            styleInformation: body == null
                ? null
                : BigTextStyleInformation(body),
          ),
          iOS: DarwinNotificationDetails(
            threadIdentifier: channel,
            presentAlert: true,
            presentBanner: true,
            presentSound: true,
            badgeNumber: _feed.unread.value,
          ),
        ),
        payload: payload,
      );
      _log('show id=${item.id} ok');
      await _updateSummary(channel);
      return true;
    } catch (e) {
      _log('show id=${item.id} failed: $e');
      return false;
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
            channelId(channel),
            info.$1,
            channelDescription: info.$2,
            icon: _smallIcon,
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
      _shown.remove(id);
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
}
