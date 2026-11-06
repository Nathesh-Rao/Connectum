import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/conversation_route.dart';
import '../../core/utils/attachment_tag.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/db/app_database.dart';
import '../../data/models/conversation.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import '../../data/socket/connectivity_service.dart';
import '../home_shell/home_shell_controller.dart';
import 'enterprise_switcher_controller.dart';
import 'models/chat_filter.dart';
import 'models/message_hit.dart';
import 'models/new_chat_button_state.dart';
import 'new_chat_controller.dart';
import 'record_rename_controller.dart';

class ChatsController extends GetxController {
  ChatsController({
    required this.conversations,
    required this.messages,
    required this.presence,
    required this.feed,
    required this.store,
    required this.connectivity,
    required this.db,
    required this.shell,
    required this.switcher,
    required this.newChat,
  });

  static const _searchDelay = Duration(milliseconds: 250);

  final ConversationRepository conversations;
  final MessageRepository messages;
  final PresenceRepository presence;
  final FeedRepository feed;
  final SessionStore store;
  final ConnectivityService connectivity;
  final AppDatabase db;
  final HomeShellController shell;
  final EnterpriseSwitcherController switcher;
  final NewChatController newChat;

  final searchField = TextEditingController();
  final searchFocus = FocusNode();

  final viewState = AppViewState.loading.obs;
  final visibleIds = <String>[].obs;
  final unreadChats = 0.obs;
  final filter = ChatFilterKind.all.obs;
  final hasThreads = false.obs;
  final threadUnread = 0.obs;
  final query = ''.obs;
  final searchConversations = <Conversation>[].obs;
  final searchMessages = <MessageHit>[].obs;
  final hasSearched = false.obs;
  final minute = DateTime.now().obs;
  final isRefreshing = false.obs;
  final newChatButton = NewChatButtonState();

  final _rows = <String, Rx<Conversation>>{};
  final _all = <String, Conversation>{};
  Timer? _minuteTimer;
  Timer? _searchTimer;
  int _searchSeq = 0;

  bool get isOffline => connectivity.state.value == AppConnectivity.offline;
  bool get isSearching => query.value.trim().isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    ever(filter, (_) {
      showNewChat();
      _apply();
    });
    ever(viewState, (_) => showNewChat());
    ever(conversations.conversations, (_) => _apply());
    ever(conversations.isLoaded, (_) => _apply());
    ever(conversations.loadError, (_) => _apply());
    ever(conversations.isSynced, (_) => _apply());
    ever(conversations.hasSyncStalled, (_) => _apply());
    ever(connectivity.state, (_) => _apply());
    ever(store.current, (_) {
      clearSearch();
      _rows.clear();
      _all.clear();
      visibleIds.clear();
      _apply();
    });
    ever(SeedUi.chatsState, (_) => _apply());
    SeedUi.releaseChatsDelay();
    _minuteTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => minute.value = DateTime.now(),
    );
    _apply();
  }

  Rx<Conversation> rowOf(String id) => _rows[id]!;

  /// Rows read for another organisation or person are never built into the
  /// list, whatever the repository still holds.
  List<Conversation> get _source {
    if (SeedUi.isActive) return SeedUi.conversations();
    if (conversations.listScope != '${store.orgId}/${store.userId}') {
      return const [];
    }
    return conversations.conversations.toList();
  }

  /// Called by the chips. The Threads chip is not offered without threads.
  void select(ChatFilterKind next) {
    filter.value = next == ChatFilterKind.threads && !hasThreads.value
        ? ChatFilterKind.all
        : next;
    if (isSearching) _runSearch();
  }

  void _apply() {
    final source = _source.where(ChatFilter.isListed).toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.lastTs.compareTo(a.lastTs);
      });
    _all
      ..clear()
      ..addEntries(source.map((c) => MapEntry(c.convId, c)));
    // A muted conversation keeps its own count but is left out of the tab
    // dot.
    unreadChats.value = source.where((c) => c.unread > 0 && !c.isMuted).length;
    final every = _source;
    hasThreads.value = ChatFilter.hasThreads(every);
    threadUnread.value = ChatFilter.threadUnread(every);
    if (filter.value == ChatFilterKind.threads && !hasThreads.value) {
      filter.value = ChatFilterKind.all;
    }
    final shown = ChatFilter.apply(source, filter.value);
    final ids = <String>[];
    for (final c in shown) {
      ids.add(c.convId);
      final rx = _rows[c.convId];
      if (rx == null) {
        _rows[c.convId] = Rx<Conversation>(c);
      } else if (rx.value != c) {
        rx.value = c;
      }
    }
    _rows.removeWhere((id, _) => !_all.containsKey(id));
    if (!_sameIds(ids)) visibleIds.assignAll(ids);
    final state = _stateFor(source.isEmpty);
    viewState.value = state == AppViewState.content && shown.isEmpty
        ? AppViewState.empty
        : state;
  }

  bool _sameIds(List<String> next) {
    if (next.length != visibleIds.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i] != visibleIds[i]) return false;
    }
    return true;
  }

  AppViewState _stateFor(bool isEmpty) {
    if (SeedUi.isActive) {
      switch (SeedUi.chatsState.value) {
        case 'loading':
          return AppViewState.loading;
        case 'empty':
          visibleIds.clear();
          return AppViewState.empty;
        case 'error':
          return AppViewState.error;
      }
      return AppViewState.content;
    }
    if (conversations.loadError.value != null) return AppViewState.error;
    if (!conversations.isLoaded.value) return AppViewState.loading;
    if (isEmpty) {
      // Empty only once we know: the server lists arrived, we are offline, or
      // the sync has taken too long (the skeleton never stays forever).
      return conversations.isSynced.value ||
              conversations.hasSyncStalled.value ||
              isOffline
          ? AppViewState.empty
          : AppViewState.loading;
    }
    return AppViewState.content;
  }

  // ---- header ----------------------------------------------------------------

  String get enterpriseName {
    final org = store.orgId ?? (SeedUi.isActive ? SeedUi.currentOrgId : null);
    final memberships = store.identity.value?.enterprises ?? const [];
    for (final m in memberships) {
      if (m.enterprise == org) return m.name;
    }
    return org ?? 'Enterprise';
  }

  String get myName {
    final identity = store.identity.value;
    if (identity != null && identity.name.isNotEmpty) return identity.name;
    return store.userId ?? identity?.username ?? '';
  }

  void openNotifications() => Get.toNamed(AppRoutes.notifications);

  void openProfile() => shell.select(3);

  void openWorkspace() => Get.toNamed(AppRoutes.workspace);

  static const needsConnection =
      'This needs a connection. Try again when you are online.';

  /// Pin, unpin, mute or unmute. Returns a plain-words problem, or null when
  /// it worked. These are kept on the server, so they need a connection.
  Future<String?> togglePin(Conversation c) => _change(
    () => conversations.setPinned(c.convId, isPinned: !c.isPinned),
    () => SeedUi.setFlags(c.convId, isPinned: !c.isPinned),
  );

  Future<String?> toggleMute(Conversation c) => _change(
    () => conversations.setMuted(c.convId, isMuted: !c.isMuted),
    () => SeedUi.setFlags(c.convId, isMuted: !c.isMuted),
  );

  Future<String?> _change(
    Future<void> Function() action,
    VoidCallback seed,
  ) async {
    if (SeedUi.isActive) {
      seed();
      return null;
    }
    if (isOffline) return needsConnection;
    try {
      await action();
      return null;
    } on SocketCallError catch (e) {
      if (e.isConnectionGap) return needsConnection;
      return e.message.isEmpty ? 'That did not work. Try again.' : e.message;
    }
  }

  /// The rename of one record conversation, for the rename sheet.
  RecordRenameController renameFor(Conversation c) => RecordRenameController(
    onRename: (name) => conversations.renameRecord(c, name),
    isOffline: () => isOffline,
  );

  void open(String convId) {
    ConversationRoute.open(convId);
  }

  AppPresenceDot presenceFor(Conversation c) {
    final peer = c.peer;
    if (peer == null) return AppPresenceDot.none;
    final isKnown = presence.isKnown.value;
    if (SeedUi.isActive) {
      return SeedUi.online.contains(peer)
          ? AppPresenceDot.online
          : SeedUi.offline.contains(peer)
          ? AppPresenceDot.offline
          : AppPresenceDot.none;
    }
    if (!isKnown) return AppPresenceDot.none;
    return switch (presence.dotFor(peer)) {
      PresenceDot.online => AppPresenceDot.online,
      PresenceDot.offline => AppPresenceDot.offline,
      PresenceDot.none => AppPresenceDot.none,
    };
  }

  // ---- new chat button -----------------------------------------------------------

  void showNewChat() => newChatButton.show();

  // ---- refresh -----------------------------------------------------------------

  Future<void> refreshList() async {
    if (isOffline) return;
    isRefreshing.value = true;
    try {
      await Future.wait([
        messages.syncNow(),
        presence.refresh(),
        feed.refresh(),
      ]);
    } finally {
      isRefreshing.value = false;
      showNewChat();
    }
  }

  Future<void> retry() async {
    if (SeedUi.isActive) {
      SeedUi.chatsState.value = 'content';
      return;
    }
    await conversations.reload();
  }

  // ---- search ------------------------------------------------------------------

  void onQueryChanged(String value) {
    query.value = value;
    hasSearched.value = false;
    _searchTimer?.cancel();
    if (value.trim().isEmpty) {
      _searchSeq++;
      searchConversations.clear();
      searchMessages.clear();
      return;
    }
    _searchTimer = Timer(_searchDelay, _runSearch);
  }

  void clearSearch() {
    searchField.clear();
    onQueryChanged('');
    showNewChat();
  }

  /// Local only, so it works offline: conversation titles and last texts, and
  /// the cached text of messages (not encrypted, not deleted, not archived).
  Future<void> _runSearch() async {
    final q = query.value.trim();
    if (q.isEmpty) return;
    final seq = ++_searchSeq;
    if (SeedUi.isActive) {
      final lower = q.toLowerCase();
      searchConversations.assignAll(
        _all.values.where(
          (c) =>
              ChatFilter.matches(filter.value, c) &&
              ChatFilter.matchesQuery(lower, c),
        ),
      );
      searchMessages.clear();
      hasSearched.value = true;
      return;
    }
    final org = store.orgId;
    final user = store.userId;
    if (org == null || user == null) return;
    final like =
        '%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
    final convRows = await db.query(
      'SELECT conv_id FROM conversations WHERE org_id = ? AND user_id = ? AND is_archived = 0 '
      "AND (title LIKE ? ESCAPE '\\' OR last_text LIKE ? ESCAPE '\\')",
      [org, user, like, like],
    );
    final messageRows = await db.query(
      'SELECT m.conv_id, m.text, m.ts, c.title FROM messages m '
      'JOIN conversations c ON c.org_id = m.org_id AND c.user_id = m.user_id AND c.conv_id = m.conv_id '
      "WHERE m.org_id = ? AND m.user_id = ? AND m.kind = 'chat' AND m.is_deleted = 0 "
      "AND m.is_encrypted_unsupported = 0 AND c.is_archived = 0 AND m.text LIKE ? ESCAPE '\\' "
      'ORDER BY m.ts DESC LIMIT 40',
      [org, user, like],
    );
    if (seq != _searchSeq) return;
    searchConversations.assignAll([
      for (final r in convRows)
        if (_all[idText(r['conv_id'])] case final c?)
          if (ChatFilter.matches(filter.value, c)) c,
    ]);
    searchMessages.assignAll([
      for (final r in messageRows)
        MessageHit(
          convId: idText(r['conv_id']),
          title: idText(r['title']),
          snippet:
              AttachmentTag.preview(idText(r['text'])) ??
              _snippet(idText(r['text']), q),
          ts: intOf(r['ts']),
        ),
    ]);
    hasSearched.value = true;
  }

  static String _snippet(String text, String q) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    final at = flat.toLowerCase().indexOf(q.toLowerCase());
    final start = at > 24 ? at - 24 : 0;
    final end = start + 90 > flat.length ? flat.length : start + 90;
    return '${start > 0 ? '…' : ''}${flat.substring(start, end)}${end < flat.length ? '…' : ''}';
  }

  @override
  void onClose() {
    _minuteTimer?.cancel();
    _searchTimer?.cancel();
    searchField.dispose();
    searchFocus.dispose();
    super.onClose();
  }
}
