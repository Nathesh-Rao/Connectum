import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/home_reload.dart';
import '../../core/utils/chat_time.dart';
import '../../data/models/conversation.dart';
import '../../data/models/message.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/typing_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import '../../core/widgets/app_avatar.dart';
import 'models/chat_item.dart';

/// One conversation. A controller exists per conversation id (the binding puts
/// it under that id as its tag), so one route's disposal can never delete
/// another conversation's controller. It owns its text controller, focus node,
/// scroll controller and timers and disposes them with the route.
class ConversationController extends GetxController
    with WidgetsBindingObserver {
  ConversationController({
    required this.conversationId,
    required this.messages,
    required this.conversations,
    required this.presence,
    required this.typing,
    required this.socket,
    required this.store,
  });

  static const maxLength = 2000;
  static const _nearBottom = 120.0;
  static const _typingEvery = Duration(seconds: 3);
  static const _readDelay = Duration(milliseconds: 400);
  static const _runGap = Duration(minutes: 5);

  final String conversationId;
  final MessageRepository messages;
  final ConversationRepository conversations;
  final PresenceRepository presence;
  final TypingRepository typing;
  final SocketService socket;
  final SessionStore store;

  final text = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  final listKey = GlobalKey();
  final unreadKey = GlobalKey();

  final items = <ChatItem>[].obs;
  final isLoaded = false.obs;
  final isLoadingOlder = false.obs;
  final hasOlderError = false.obs;
  final hasMore = RxnBool();
  final isRetired = false.obs;
  final isBlocked = false.obs;
  final isAway = false.obs;
  final newAway = 0.obs;
  final length = 0.obs;
  final reply = Rxn<Message>();
  final notice = RxnString();

  final _byId = <String, Message>{};
  final _seen = <String>{};
  final _fresh = <String>{};
  RxList<Message>? _list;
  Worker? _listWorker;
  Worker? _onlineWorker;
  Timer? _readTimer;
  Timer? _noticeTimer;
  Timer? _seedTimer;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
  String? _firstUnreadId;
  int _unreadCount = 0;
  bool _isUnreadMore = false;
  bool _isForeground = true;

  // ---- who this is ---------------------------------------------------------

  String get kind => ConversationRepository.kindOf(conversationId);
  String get target => ConversationRepository.targetOf(conversationId);
  bool get isDirect => kind == 'dm';
  bool get isTeam => kind == 'host';
  bool get canReply => isDirect || kind == 'group';
  bool get canDelete => kind != 'host';
  bool get canType => kind != 'host';
  bool get isOnline => socket.isOnline;
  String get me => (store.userId ?? SeedMessages.me).toLowerCase();

  Conversation? get conversation {
    final rows = SeedUi.isActive
        ? SeedUi.conversations()
        : conversations.conversations;
    for (final c in rows) {
      if (c.convId == conversationId) return c;
    }
    return null;
  }

  String get title {
    final t = conversation?.title ?? '';
    return t.isEmpty ? (kind == 'global' ? 'Everyone' : target) : t;
  }

  /// The header's second line. A direct message shows "Active now" only while
  /// presence is live and the socket is online; a group shows its member
  /// count when known. Reads Rx values: call it inside an Obx.
  String? get status {
    if (isDirect) {
      final dot = SeedUi.isActive
          ? (SeedUi.online.contains(target)
                ? AppPresenceDot.online
                : AppPresenceDot.none)
          : switch (presence.dotFor(target)) {
              PresenceDot.online => AppPresenceDot.online,
              _ => AppPresenceDot.none,
            };
      return dot == AppPresenceDot.online ? 'Active now' : null;
    }
    final count = conversation?.memberCount ?? 0;
    return kind == 'group' && count > 0 ? '$count members' : null;
  }

  AppPresenceDot get presenceDot {
    if (!isDirect) return AppPresenceDot.none;
    if (SeedUi.isActive) {
      return SeedUi.online.contains(target)
          ? AppPresenceDot.online
          : AppPresenceDot.none;
    }
    return switch (presence.dotFor(target)) {
      PresenceDot.online => AppPresenceDot.online,
      PresenceDot.offline => AppPresenceDot.offline,
      PresenceDot.none => AppPresenceDot.none,
    };
  }

  /// A key that is unique across open conversations: message ids repeat
  /// between conversations, and two can be mounted at once.
  GlobalKey keyFor(ChatItem item) =>
      GlobalObjectKey('$conversationId|${item.key}');

  Message? originalOf(Message m) => m.replyTo == null ? null : _byId[m.replyTo];

  /// "Priya is typing", "Priya and Ravi are typing", or null.
  String? get typingLabel {
    final list = typing.typingIn(conversationId);
    if (list.isEmpty) return null;
    final names = [
      for (var i = 0; i < list.length; i++)
        if (list[i].toLowerCase() != me) list[i],
    ];
    if (names.isEmpty) return null;
    if (names.length == 1) return '${names.first} is typing';
    return '${names.take(2).join(' and ')} are typing';
  }

  // ---- lifecycle -----------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    scroll.addListener(_onScroll);
    _onlineWorker = ever(socket.connection, (state) {
      if (state == SocketState.online && !SeedUi.isActive) _sync();
    });
    _load();
  }

  Future<void> _load() async {
    final unread = conversation;
    _unreadCount = unread?.unread ?? 0;
    _isUnreadMore = unread?.unreadMore ?? false;
    if (SeedUi.isActive) {
      _list = SeedMessages.of(conversationId);
      hasMore.value = false;
      isBlocked.value = conversation?.isEncrypted ?? false;
      _startSeedTimers();
    } else {
      _list = await messages.open(conversationId);
      isBlocked.value = await messages.isEncrypted(conversationId);
    }
    final list = _list!;
    _firstUnreadId = _firstUnread(list.toList());
    _rebuild(isFirst: true);
    isLoaded.value = true;
    _listWorker = ever(list, (_) => _rebuild());
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialScroll());
    if (!SeedUi.isActive) {
      unawaited(_checkEncryptedOnline());
      unawaited(_sync());
    }
  }

  Future<void> _checkEncryptedOnline() async {
    if (!socket.isOnline) return;
    final encrypted = await messages.isEncrypted(
      conversationId,
      isLookup: true,
    );
    if (encrypted != isBlocked.value) isBlocked.value = encrypted;
  }

  /// The light sync on entering: the latest page, when online.
  Future<void> _sync() async {
    if (!socket.isOnline) return;
    await messages.syncConversation(conversationId);
    final state = await messages.olderState(conversationId);
    hasMore.value = state.hasMore;
    _rebuild();
  }

  void _startSeedTimers() {
    if (conversationId != 'dm:priya') return;
    typing.simulate(conversationId, 'Priya');
    var n = 0;
    _seedTimer = Timer.periodic(const Duration(seconds: 4), (t) {
      n++;
      if (n == 3) {
        SeedMessages.incoming(conversationId, 'priya', 'Sounds good, thanks!');
      } else if (n < 3) {
        typing.simulate(conversationId, 'Priya');
      } else {
        t.cancel();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) _scheduleRead();
  }

  /// Takes this screen down before its controller closes (a home reload).
  void retire() => isRetired.value = true;

  // ---- building the rows ---------------------------------------------------

  String? _firstUnread(List<Message> asc) {
    if (_unreadCount <= 0) return null;
    final others = asc.where((m) => !m.isMine && !m.isLocalTemp).toList();
    if (others.isEmpty) return null;
    return others[math.max(0, others.length - _unreadCount)].msgId;
  }

  String get _unreadLabel => _isUnreadMore || _unreadCount > 99
      ? '99+ new messages'
      : _unreadCount == 1
      ? '1 new message'
      : '$_unreadCount new messages';

  void _rebuild({bool isFirst = false}) {
    final list = _list;
    if (list == null) return;
    final asc = list.toList();
    final now = DateTime.now();
    _byId
      ..clear()
      ..addEntries(asc.map((m) => MapEntry(m.msgId, m)));
    final near = !isAway.value;
    for (final m in asc) {
      final key = m.cid ?? m.msgId;
      if (_seen.add(key) && !isFirst) {
        if (near || m.isMine) {
          _fresh.add(key);
        } else if (!m.isMine) {
          newAway.value++;
        }
      }
    }
    final out = <ChatItem>[];
    Message? prev;
    for (var i = 0; i < asc.length; i++) {
      final m = asc[i];
      final isNewDay = prev == null || !ChatTime.isSameDay(prev.ts, m.ts);
      if (isNewDay) out.add(ChatItem.day(ChatTime.day(m.ts, now)));
      final isUnreadStart = m.msgId == _firstUnreadId;
      if (isUnreadStart) out.add(ChatItem.unread(_unreadLabel));
      final next = i + 1 < asc.length ? asc[i + 1] : null;
      final startsRun =
          prev == null || isNewDay || isUnreadStart || _breaks(prev, m);
      final endsRun =
          next == null ||
          !ChatTime.isSameDay(m.ts, next.ts) ||
          next.msgId == _firstUnreadId ||
          _breaks(m, next);
      out.add(
        ChatItem.message(
          m,
          isFirstOfRun: startsRun,
          isLastOfRun: endsRun,
          showName: !m.isMine && !isDirect && startsRun,
          isFresh: _fresh.contains(m.cid ?? m.msgId),
        ),
      );
      prev = m;
    }
    final reversed = out.reversed.toList();
    if (isLoadingOlder.value) {
      reversed.add(const ChatItem.status(ChatItemKind.loadingOlder));
    } else if (hasOlderError.value) {
      reversed.add(const ChatItem.status(ChatItemKind.olderError));
    } else if (hasMore.value == false && asc.isNotEmpty) {
      reversed.add(const ChatItem.status(ChatItemKind.start));
    }
    items.assignAll(reversed);
    _scheduleRead();
  }

  bool _breaks(Message a, Message b) =>
      a.isMine != b.isMine ||
      a.sender != b.sender ||
      (b.ts - a.ts) > _runGap.inMilliseconds;

  // ---- scrolling -----------------------------------------------------------

  void _onScroll() {
    if (!scroll.hasClients) return;
    final p = scroll.position;
    final away = p.pixels > _nearBottom;
    if (away != isAway.value) isAway.value = away;
    if (!away) newAway.value = 0;
    if (p.maxScrollExtent - p.pixels < 400) unawaited(loadOlder());
    _scheduleRead();
  }

  void scrollToLatest() {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Opens at the "new messages" divider when there is unread, otherwise at
  /// the newest message (offset 0 of the reversed list).
  Future<void> _initialScroll() async {
    if (_firstUnreadId == null || !scroll.hasClients) return;
    for (var i = 0; i < 40; i++) {
      final context = unreadKey.currentContext;
      if (context != null && context.mounted) {
        await Scrollable.ensureVisible(context, alignment: 0.25);
        return;
      }
      final p = scroll.position;
      if (p.pixels >= p.maxScrollExtent) return;
      scroll.jumpTo(
        math.min(p.maxScrollExtent, p.pixels + p.viewportDimension * 0.8),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> loadOlder() async {
    if (SeedUi.isActive ||
        isLoadingOlder.value ||
        hasMore.value == false ||
        !socket.isOnline ||
        !isLoaded.value) {
      return;
    }
    isLoadingOlder.value = true;
    hasOlderError.value = false;
    _rebuild();
    final page = await messages.loadOlder(conversationId);
    isLoadingOlder.value = false;
    if (page == null) {
      hasOlderError.value = socket.isOnline;
    } else {
      hasMore.value = page.hasMore;
    }
    _rebuild();
  }

  Future<void> retryOlder() {
    hasOlderError.value = false;
    return loadOlder();
  }

  // ---- read ----------------------------------------------------------------

  /// Reports the newest message from someone else that is on screen, only
  /// while the app is in the foreground and this is the conversation on top.
  /// Going back, backgrounding or being offline never reports a message that
  /// was not seen; the position is only ever moved forward by the repository.
  void _scheduleRead() {
    _readTimer?.cancel();
    _readTimer = Timer(_readDelay, _markVisibleRead);
  }

  void _markVisibleRead() {
    if (!_isForeground || !isLoaded.value || isRetired.value) return;
    if (Get.currentRoute != AppRoutes.conversationOf(conversationId)) return;
    final box = listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final top = items.take(40).toList();
    for (final item in top) {
      final m = item.message;
      if (m == null || m.isMine || m.isLocalTemp) continue;
      final ctx = keyFor(item).currentContext;
      final render = ctx?.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final y = render.localToGlobal(Offset.zero, ancestor: box).dy;
      final visible =
          math.min(y + render.size.height, box.size.height) - math.max(y, 0);
      if (visible >= render.size.height * 0.6) {
        if (SeedUi.isActive) return;
        unawaited(conversations.markRead(conversationId, m.msgId));
        return;
      }
    }
  }

  // ---- composing -----------------------------------------------------------

  void onChanged(String value) {
    length.value = value.characters.length;
    if (value.trim().isEmpty || !canType || !socket.isOnline) return;
    final now = DateTime.now();
    if (now.difference(_lastTyping) < _typingEvery) return;
    _lastTyping = now;
    final command = switch (kind) {
      'dm' => '/typing dm $target',
      'group' => '/typing group $target',
      'global' => '/typing global',
      _ => null,
    };
    if (command != null) unawaited(socket.sendCommand(command));
  }

  bool get canSend {
    final n = length.value;
    return text.text.trim().isNotEmpty && n <= maxLength;
  }

  void _say(String message) {
    notice.value = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () => notice.value = null);
  }

  Future<void> send() async {
    final body = text.text.trim();
    if (body.isEmpty) return;
    if (body.characters.length > maxLength) {
      _say('Messages can be up to $maxLength characters.');
      return;
    }
    final replyTo = reply.value?.msgId;
    text.clear();
    length.value = 0;
    reply.value = null;
    _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
    if (SeedUi.isActive) {
      SeedMessages.send(conversationId, body, replyTo: replyTo);
    } else {
      final result = await messages.sendText(
        conversationId,
        body,
        replyTo: replyTo,
      );
      switch (result) {
        case SendResult.blockedEncrypted:
          isBlocked.value = true;
        case SendResult.tooLong:
          _say('Messages can be up to $maxLength characters.');
        case SendResult.invalid:
        case SendResult.noSession:
          _say("That message couldn't be sent.");
        case SendResult.queued:
          break;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => scrollToLatest());
  }

  void tapPlaceholder() => _say('Coming soon');

  void startReply(Message m) {
    reply.value = m;
    focus.requestFocus();
  }

  void clearReply() => reply.value = null;

  Future<void> retry(Message m) async {
    if (SeedUi.isActive) {
      SeedMessages.retry(conversationId, m.msgId);
    } else {
      await messages.retry(m.msgId);
    }
  }

  Future<void> copy(Message m) =>
      Clipboard.setData(ClipboardData(text: m.text));

  /// Deletes one of my messages. Returns a plain-words problem, or null.
  Future<String?> delete(Message m) async {
    if (SeedUi.isActive) {
      SeedMessages.delete(conversationId, m.msgId);
      return null;
    }
    final result = await messages.deleteMessage(m);
    return switch (result) {
      DeleteResult.deleted => null,
      DeleteResult.denied => "You can't delete that message.",
      DeleteResult.needsConnection =>
        'Deleting needs a connection. Try again when you are online.',
      DeleteResult.notSupported => "Messages can't be deleted here.",
      DeleteResult.failed => "That didn't work. Try again.",
    };
  }

  @override
  void onClose() {
    HomeReload.overlays.remove(conversationId);
    WidgetsBinding.instance.removeObserver(this);
    _readTimer?.cancel();
    _noticeTimer?.cancel();
    _seedTimer?.cancel();
    _listWorker?.dispose();
    _onlineWorker?.dispose();
    scroll.removeListener(_onScroll);
    scroll.dispose();
    text.dispose();
    focus.dispose();
    super.onClose();
  }
}
