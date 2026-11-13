import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../data/api/api_client.dart';
import '../../data/models/conversation.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'models/chat_person.dart';

class NewChatController extends GetxController {
  NewChatController({
    required this.conversations,
    required this.socket,
    required this.api,
    required this.store,
    required this.connectivity,
  });

  final ConversationRepository conversations;
  final SocketService socket;
  final ApiClient api;
  final SessionStore store;
  final ConnectivityService connectivity;

  final queryField = TextEditingController();
  final query = ''.obs;
  final hits = <ChatPerson>[].obs;
  final connections = <ChatPerson>[].obs;
  final isSearching = false.obs;
  final explanation = RxnString();

  /// The names in [explanation] (`{name}`).
  Map<String, String> explanationValues = const {};

  /// `strict` or `open`, from `GET /session`. Null when not known.
  String? _mode;
  Timer? _debounce;
  int _seq = 0;

  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  /// People from my direct conversations and my connections, filtered by what
  /// is typed. Search hits (people I may not know yet) come after.
  List<ChatPerson> get people {
    final q = query.value.trim().toLowerCase();
    final seen = <String>{};
    final list = <ChatPerson>[];
    void add(ChatPerson p) {
      if (!seen.add(p.username.toLowerCase())) return;
      if (q.isEmpty ||
          p.username.toLowerCase().contains(q) ||
          p.name.toLowerCase().contains(q)) {
        list.add(p);
      }
    }

    for (final c in _source) {
      if (c.kind == 'dm' && !c.isArchived) {
        add(
          ChatPerson(username: c.peer!, name: c.title, source: 'conversation'),
        );
      }
    }
    connections.forEach(add);
    hits.forEach(add);
    return list;
  }

  Iterable<Conversation> get _source {
    if (SeedUi.isActive) return SeedUi.conversations();
    if (conversations.listScope != '${store.orgId}/${store.userId}') {
      return const [];
    }
    return conversations.conversations;
  }

  /// Called when the sheet opens.
  Future<void> prepare() async {
    queryField.clear();
    query.value = '';
    hits.clear();
    connections.clear();
    explanation.value = null;
    if (isOffline || !socket.isOnline) return;
    try {
      final data = await api.session();
      _mode = idText(data['mode']);
    } on ApiException catch (_) {}
    try {
      final data = await socket.sdCall('assoc.list', {});
      connections.assignAll([
        for (final a in (data['associates'] as List? ?? []).whereType<Map>())
          if (a['user'] is Map)
            ChatPerson(
              username: idText((a['user'] as Map)['username']),
              name: _nameOf(a['user'] as Map),
              source: 'connection',
            ),
      ]);
    } on SocketCallError catch (_) {}
  }

  void onQueryChanged(String value) {
    query.value = value;
    explanation.value = null;
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      _seq++;
      hits.clear();
      isSearching.value = false;
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  /// `users.search` finds a person by exact username, email or mobile in a
  /// strict enterprise, and by name in an open one. A row has username, name
  /// and canInteract; every field is read defensively.
  Future<void> _search(String q) async {
    if (isOffline || !socket.isOnline) return;
    final seq = ++_seq;
    isSearching.value = true;
    try {
      final data = await socket.sdCall('users.search', {'q': q});
      if (seq != _seq) return;
      final me = (store.userId ?? '').toLowerCase();
      hits.assignAll([
        for (final u in (data['users'] as List? ?? []).whereType<Map>())
          if (idText(u['username']).isNotEmpty &&
              idText(u['username']).toLowerCase() != me)
            ChatPerson(
              username: idText(u['username']),
              name: _nameOf(u),
              source: 'search',
              canInteract: u['canInteract'] is bool
                  ? u['canInteract'] as bool
                  : null,
            ),
      ]);
    } on SocketCallError catch (_) {
      if (seq == _seq) hits.clear();
    } finally {
      if (seq == _seq) isSearching.value = false;
    }
  }

  static String _nameOf(Map u) {
    final name = idText(u['name']);
    return name.isNotEmpty ? name : idText(u['username']);
  }

  /// Opens the direct message, or says in plain words why it cannot be
  /// opened yet. A person I already talk to or am connected with is always
  /// allowed. A new person is refused by the interaction rules
  /// (`canInteract: false`), and in a strict enterprise unless I am connected
  /// to them, they are my host or an administrator (which the app cannot tell).
  void start(ChatPerson person) {
    explanation.value = null;
    if (!person.isKnown) {
      if (person.canInteract == false) {
        explanationValues = {'name': person.name};
        explanation.value =
            "This organisation's rules don't allow you to message {name}.";
        return;
      }
      if (_mode == 'strict') {
        explanationValues = {'name': person.name};
        explanation.value =
            "{name} isn't one of your connections yet. In this enterprise you can message your host, administrators and people you're connected with. Connecting with someone isn't available in the app yet.";
        return;
      }
    }
    Get.back<void>();
    Get.toNamed(
      AppRoutes.conversationOf('dm:${person.username.toLowerCase()}'),
    );
  }

  void openNewGroup() {
    Get.back<void>();
    Get.toNamed(AppRoutes.newGroup);
  }

  @override
  void onClose() {
    _debounce?.cancel();
    queryField.dispose();
    super.onClose();
  }
}
