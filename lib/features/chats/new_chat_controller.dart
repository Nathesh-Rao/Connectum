import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/log/app_log.dart';
import '../../core/log/safe.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/api/api_client.dart';
import '../../data/models/conversation.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'models/chat_person.dart';
import 'models/person_link.dart';

class NewChatController extends GetxController {
  NewChatController({
    required this.conversations,
    required this.people,
    required this.socket,
    required this.api,
    required this.store,
    required this.connectivity,
  });

  static const searchDelay = Duration(milliseconds: 300);

  /// A typed query of this length also asks `users.search` (an exact
  /// username, e-mail or mobile number outside the paged list).
  static const exactSearchLength = 3;

  final ConversationRepository conversations;
  final PeopleRepository people;
  final SocketService socket;
  final ApiClient api;
  final SessionStore store;
  final ConnectivityService connectivity;

  final queryField = TextEditingController();
  final query = ''.obs;

  /// My connections (`assoc.list`).
  final connections = <ChatPerson>[].obs;

  /// The pages of `users.colleagues` read so far for the current query,
  /// connected or not.
  final colleagues = <ChatPerson>[].obs;

  /// `users.search` hits for the current query.
  final hits = <ChatPerson>[].obs;

  /// Link of each person (lower-case username) found in a pending request or
  /// changed by an event. A person not in the map has no link.
  final links = <String, PersonLink>{}.obs;

  /// People a request is being sent to now (lower-case username).
  final sending = <String>{}.obs;

  final isLoading = false.obs;
  final hasFailed = false.obs;
  final isLoadingMore = false.obs;
  final hasLoadMoreFailed = false.obs;
  final hasMore = false.obs;
  final explanation = RxnString();

  /// Why the last people read failed (the server's reason in plain words).
  final failureReason = RxnString();

  /// The names in [explanation] (`{name}`).
  Map<String, String> explanationValues = const {};

  /// `strict` or `open`, from `GET /session`. Null when not known.
  String? _mode;
  Timer? _debounce;
  StreamSubscription<Map<String, dynamic>>? _events;
  String? _next;
  int _seq = 0;

  // The list for an empty query, kept while a search is typed so clearing the
  // field does not read it again.
  List<ChatPerson>? _idleRows;
  String? _idleNext;
  bool _idleHasMore = false;

  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  String get _me => (store.userId ?? '').toLowerCase();

  @override
  void onInit() {
    super.onInit();
    _events = socket.events.listen(onSocketEvent);
  }

  PersonLink linkOf(ChatPerson p) {
    if (p.source == 'conversation' || p.source == 'connection') {
      return PersonLink.connected;
    }
    return links[p.username.toLowerCase()] ?? PersonLink.none;
  }

  /// Every person to show, once each: my direct chats and connections first,
  /// then the paged list and the exact hits.
  List<ChatPerson> get _all {
    final q = query.value.trim().toLowerCase();
    final seen = <String>{};
    final list = <ChatPerson>[];
    void add(ChatPerson p, {required bool isLocalMatch}) {
      if (p.username.toLowerCase() == _me) return;
      if (isLocalMatch &&
          q.isNotEmpty &&
          !p.username.toLowerCase().contains(q) &&
          !p.name.toLowerCase().contains(q)) {
        return;
      }
      if (seen.add(p.username.toLowerCase())) list.add(p);
    }

    for (final c in _source) {
      if (c.kind == 'dm' && !c.isArchived) {
        add(
          ChatPerson(username: c.peer!, name: c.title, source: 'conversation'),
          isLocalMatch: true,
        );
      }
    }
    for (final p in connections) {
      add(p, isLocalMatch: true);
    }
    for (final p in colleagues) {
      add(p, isLocalMatch: false);
    }
    for (final p in hits) {
      add(p, isLocalMatch: false);
    }
    return list;
  }

  /// Connected people, at the top.
  List<ChatPerson> get connectedPeople => [
    for (final p in _all)
      if (linkOf(p) == PersonLink.connected) p,
  ];

  /// People not connected yet, in the "Not connected" section.
  List<ChatPerson> get otherPeople => [
    for (final p in _all)
      if (linkOf(p) != PersonLink.connected) p,
  ];

  bool get hasPeople => _all.isNotEmpty;

  /// What the list area shows. Rows already read stay on screen when a later
  /// read fails.
  AppViewState get listState {
    if (hasPeople) return AppViewState.content;
    if (isLoading.value) return AppViewState.loading;
    if (hasFailed.value) return AppViewState.error;
    return query.value.trim().isEmpty
        ? AppViewState.empty
        : AppViewState.noResults;
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
    _debounce?.cancel();
    final seq = ++_seq;
    queryField.clear();
    query.value = '';
    colleagues.clear();
    hits.clear();
    connections.clear();
    explanation.value = null;
    _idleRows = null;
    _resetPaging();
    hasFailed.value = false;
    if (isOffline || !socket.isOnline) {
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    await Future.wait([
      _loadMode(),
      _loadFirstPage(seq, ''),
      _loadLinks(),
      _loadConnections(seq),
    ]);
  }

  Future<void> _loadMode() async {
    try {
      final data = await api.session();
      _mode = idText(data['mode']);
    } on ApiException catch (e) {
      AppLog.w('new_chat_controller', '${e.runtimeType}');
    } catch (e, st) {
      AppLog.e('new_chat_controller', e, st);
    }
  }

  Future<void> _loadConnections(int seq) async {
    try {
      final list = await people.connections();
      if (seq == _seq) connections.assignAll(list);
    } on SocketCallError catch (e) {
      AppLog.w('new_chat_controller', 'socket ${e.code}');
    } catch (e, st) {
      AppLog.e('new_chat_controller', e, st);
    }
  }

  /// Joins my pending requests to the rows. A request answered meanwhile is
  /// dropped; a request being sent now is kept.
  Future<void> _loadLinks() async {
    try {
      final read = await people.pendingLinks(_me);
      final merged = <String, PersonLink>{
        for (final e in links.entries)
          if (e.value == PersonLink.connected || sending.contains(e.key))
            e.key: e.value,
        ...read,
      };
      links.assignAll(merged);
    } on SocketCallError catch (e) {
      AppLog.w('new_chat_controller', 'socket ${e.code}');
    } catch (e, st) {
      AppLog.e('new_chat_controller', e, st);
    }
  }

  void _resetPaging() {
    _next = null;
    hasMore.value = false;
    isLoadingMore.value = false;
    hasLoadMoreFailed.value = false;
  }

  Future<void> _loadFirstPage(int seq, String q) async {
    isLoading.value = true;
    hasFailed.value = false;
    failureReason.value = null;
    try {
      final page = await people.colleagues(query: q);
      if (seq != _seq) return;
      colleagues.assignAll(page.people);
      hasMore.value = page.hasMore;
      _next = page.next;
    } on SocketCallError catch (e) {
      AppLog.w('new_chat_controller', 'socket ${e.code}');
      if (seq == _seq) _fail(e);
    } catch (e, st) {
      AppLog.e('new_chat_controller', e, st);
      if (seq == _seq) _fail(e);
    } finally {
      if (seq == _seq) isLoading.value = false;
    }
  }

  void _fail(Object e) {
    hasFailed.value = true;
    failureReason.value = PeopleRepository.explainRead(e);
  }

  void _failMore(Object e) {
    hasLoadMoreFailed.value = true;
    failureReason.value = PeopleRepository.explainRead(e);
  }

  /// Retry of a failed first page.
  Future<void> retry() async {
    final seq = ++_seq;
    _resetPaging();
    await Future.wait([_loadFirstPage(seq, query.value.trim()), _loadLinks()]);
  }

  /// The next page of `users.colleagues`, asked when the list scrolls near
  /// its end. One page at a time.
  Future<void> loadMore() async {
    final after = _next;
    if (!hasMore.value ||
        after == null ||
        isLoading.value ||
        isLoadingMore.value ||
        hasLoadMoreFailed.value ||
        isOffline ||
        !socket.isOnline) {
      return;
    }
    final seq = _seq;
    isLoadingMore.value = true;
    failureReason.value = null;
    try {
      final page = await people.colleagues(
        query: query.value.trim(),
        after: after,
      );
      if (seq != _seq) return;
      final have = {for (final p in colleagues) p.username.toLowerCase()};
      colleagues.addAll([
        for (final p in page.people)
          if (!have.contains(p.username.toLowerCase())) p,
      ]);
      hasMore.value = page.hasMore;
      _next = page.next;
    } on SocketCallError catch (e) {
      AppLog.w('new_chat_controller', 'socket ${e.code}');
      if (seq == _seq) _failMore(e);
    } catch (e, st) {
      AppLog.e('new_chat_controller', e, st);
      if (seq == _seq) _failMore(e);
    } finally {
      if (seq == _seq) isLoadingMore.value = false;
    }
  }

  void retryMore() {
    hasLoadMoreFailed.value = false;
    loadMore();
  }

  void onQueryChanged(String value) {
    final before = query.value.trim();
    query.value = value;
    explanation.value = null;
    _debounce?.cancel();
    final q = value.trim();
    if (before.isEmpty && q.isNotEmpty) {
      _idleRows = colleagues.toList();
      _idleNext = _next;
      _idleHasMore = hasMore.value;
    }
    if (q.isEmpty) {
      _seq++;
      hits.clear();
      final idle = _idleRows;
      if (idle != null) {
        colleagues.assignAll(idle);
        _next = _idleNext;
        hasMore.value = _idleHasMore;
        isLoadingMore.value = false;
        hasLoadMoreFailed.value = false;
        hasFailed.value = false;
        isLoading.value = false;
        return;
      }
    }
    _debounce = Timer(searchDelay, () => search(q));
  }

  /// Reads the first page for [q] (the server narrows by name, username,
  /// designation and department) and, from three letters, the exact search.
  Future<void> search(String q) async {
    if (isOffline || !socket.isOnline) return;
    final seq = ++_seq;
    _resetPaging();
    hits.clear();
    await _loadFirstPage(seq, q);
    if (seq != _seq || q.length < exactSearchLength) return;
    try {
      final found = await people.search(q);
      if (seq != _seq) return;
      hits.assignAll(found);
    } on SocketCallError catch (e) {
      AppLog.w('new_chat_controller', 'socket ${e.code}');
    } catch (e, st) {
      AppLog.e('new_chat_controller', e, st);
    }
  }

  /// Asks [person] to connect. The row shows Requested at once; a refusal
  /// (see [PeopleRepository.explain]) puts it back, or moves it to what the
  /// server says it already is. A second tap while sending does nothing.
  Future<void> connect(ChatPerson person) async {
    final key = person.username.toLowerCase();
    if (sending.contains(key) || linkOf(person) != PersonLink.none) return;
    explanation.value = null;
    if (isOffline || !socket.isOnline) {
      _say("Sending a request needs a connection.", person);
      return;
    }
    sending.add(key);
    links[key] = PersonLink.requested;
    try {
      await people.invite(person.username);
    } on SocketCallError catch (e) {
      AppLog.w('new_chat_controller', 'invite ${e.code}');
      final error = PeopleRepository.explain(e);
      switch (error.fix) {
        case InviteFix.rollBack:
          _rollBack(key);
        case InviteFix.isRequested:
          links[key] = PersonLink.requested;
        case InviteFix.isConnected:
          links[key] = PersonLink.connected;
      }
      _say(error.message, person);
      if (e.code == 'timeout') fireAndLog('new_chat_controller', _loadLinks);
    } catch (e, st) {
      AppLog.e('new_chat_controller', e, st);
      _rollBack(key);
      _say("Couldn't send the request to {name}. Try again.", person);
    } finally {
      sending.remove(key);
    }
  }

  void _rollBack(String key) {
    if (links[key] == PersonLink.requested) links.remove(key);
  }

  void _say(String text, ChatPerson person) {
    explanationValues = {'name': person.name};
    explanation.value = text;
  }

  /// `request_created` / `request_resolved` of a connection request.
  @visibleForTesting
  void onSocketEvent(Map<String, dynamic> event) {
    final change = PeopleRepository.linkChange(event, _me);
    if (change == null) return;
    final now = links[change.username];
    switch (change.link) {
      case PersonLink.connected:
        links[change.username] = PersonLink.connected;
      case PersonLink.none:
        if (now == PersonLink.requested || now == PersonLink.asked) {
          links.remove(change.username);
        }
      case PersonLink.requested || PersonLink.asked:
        if (now == null) links[change.username] = change.link;
    }
  }

  /// Opens the direct message, or says in plain words why it cannot be
  /// opened yet. A connected person is always allowed. Anyone else is refused
  /// by the interaction rules (`canInteract: false`) and, in a strict
  /// enterprise, until they accept a connection request.
  void start(ChatPerson person) {
    explanation.value = null;
    if (linkOf(person) != PersonLink.connected) {
      if (person.canInteract == false) {
        explanationValues = {'name': person.name};
        explanation.value =
            "This organisation's rules don't allow you to message {name}.";
        return;
      }
      if (_mode == 'strict') {
        explanationValues = {'name': person.name};
        explanation.value = linkOf(person) == PersonLink.requested
            ? 'Your request to {name} is waiting for their answer. You can message them once they accept.'
            : "{name} isn't one of your connections yet. Send a connection request to message them.";
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
    _events?.cancel();
    queryField.dispose();
    super.onClose();
  }
}
