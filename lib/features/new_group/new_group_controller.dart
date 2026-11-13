import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/group_add.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../chats/models/chat_person.dart';

enum NewGroupPhase { editing, creating, adding, unconfirmed, done }

/// The Create group screen, and the same screen as "Add people" when it is
/// given [existingGroup]. Everything is online only and never queued.
class NewGroupController extends GetxController {
  NewGroupController({
    required this.groups,
    required this.conversations,
    required this.connectivity,
    required this.store,
    this.existingGroup,
  });

  final GroupRepository groups;
  final ConversationRepository conversations;
  final ConnectivityService connectivity;
  final SessionStore store;

  /// Set when people are added to a group that already exists.
  final String? existingGroup;

  final nameField = TextEditingController();
  final queryField = TextEditingController();
  final name = ''.obs;
  final phase = NewGroupPhase.editing.obs;
  final notice = RxnString();
  String? _lastNotice;

  final listState = AppViewState.loading.obs;
  final people = <ChatPerson>[].obs;
  final extras = <ChatPerson>[].obs;
  final selected = <ChatPerson>[].obs;
  final hasMore = false.obs;
  final isLoadingMore = false.obs;

  final results = <GroupAddResult>[].obs;
  final progress = 0.obs;
  final total = 0.obs;

  /// Set when the check after a lost reply got no answer either.
  final unconfirmedText = RxnString();
  final isChecking = false.obs;

  String _query = '';
  String? _next;
  Timer? _debounce;
  int _seq = 0;
  String? _createdName;

  bool get isAddingToExisting => existingGroup != null;

  String get groupName => existingGroup ?? _createdName ?? '';

  bool get isBusy =>
      phase.value == NewGroupPhase.creating ||
      phase.value == NewGroupPhase.adding;

  bool get isOffline => SeedUi.isActive
      ? SeedUi.newGroupOffline.value
      : connectivity.state.value == AppConnectivity.offline;

  String get me => (store.userId ?? '').toLowerCase();

  /// The cleaned name that would be sent.
  String get cleanName => GroupRepository.normalize(name.value);

  /// A rule the typed name breaks, or null. Reads Rx values.
  String? get nameProblem {
    if (isAddingToExisting) return null;
    final clean = cleanName;
    if (clean.isEmpty) return null;
    return GroupRepository.checkName(clean, _knownGroups);
  }

  Iterable<String> get _knownGroups sync* {
    final list = SeedUi.isActive
        ? SeedUi.conversations()
        : conversations.conversations;
    for (final c in list) {
      if (c.kind == 'group') yield c.convId.substring(6);
    }
  }

  /// Members the group has now (just me for a new one).
  int get currentMembers {
    if (!isAddingToExisting) return 1;
    for (final c in conversations.conversations) {
      if (c.convId == 'group:$existingGroup') return c.memberCount;
    }
    return 1;
  }

  bool get isOverEncryptionLimit =>
      currentMembers + selected.length > GroupRepository.maxEncryptedMembers;

  bool get canSubmit =>
      !isBusy &&
      (isAddingToExisting
          ? selected.isNotEmpty
          : cleanName.isNotEmpty && nameProblem == null);

  @override
  void onInit() {
    super.onInit();
    ever(notice, (text) {
      if (text == null) {
        AppNotices.hide(_lastNotice ?? '');
        return;
      }
      _lastNotice = text;
      if (phase.value != NewGroupPhase.done) {
        AppNotices.show(text, onDismiss: () => notice.value = null);
      }
    });
    loadPeople();
  }

  void onNameChanged(String value) {
    name.value = value;
    notice.value = null;
  }

  void onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _query = value.trim();
      loadPeople();
    });
  }

  // ---- people ----------------------------------------------------------------

  Set<String> get _skip {
    if (!isAddingToExisting) return {me};
    for (final c in conversations.conversations) {
      if (c.convId == 'group:$existingGroup') {
        return {me, ...c.members.map((m) => m.toLowerCase())};
      }
    }
    return {me};
  }

  Iterable<ChatPerson> _withoutMembers(Iterable<ChatPerson> list) {
    final skip = _skip;
    return list.where((p) => !skip.contains(p.username.toLowerCase()));
  }

  Future<void> loadPeople() async {
    final seq = ++_seq;
    extras.clear();
    _next = null;
    hasMore.value = false;
    if (isOffline) {
      listState.value = AppViewState.offline;
      return;
    }
    listState.value = AppViewState.loading;
    try {
      final page = await groups.colleagues(query: _query);
      if (seq != _seq) return;
      people.assignAll(_withoutMembers(page.people));
      hasMore.value = page.hasMore;
      _next = page.next;
      listState.value = people.isEmpty && _query.length < 3
          ? (_query.isEmpty ? AppViewState.empty : AppViewState.noResults)
          : AppViewState.content;
    } on SocketCallError catch (_) {
      if (seq == _seq) listState.value = AppViewState.error;
      return;
    }
    if (_query.length >= 3) await _loadExtras(seq);
  }

  /// People outside the colleagues list, found by a typed query of 3 or more.
  Future<void> _loadExtras(int seq) async {
    try {
      final found = await groups.search(_query);
      if (seq != _seq) return;
      final listed = {for (final p in people) p.username.toLowerCase()};
      extras.assignAll(
        _withoutMembers(
          found.where((p) => !listed.contains(p.username.toLowerCase())),
        ),
      );
    } on SocketCallError catch (_) {
      if (seq != _seq) return;
    }
    listState.value = people.isEmpty && extras.isEmpty
        ? AppViewState.noResults
        : AppViewState.content;
  }

  Future<void> loadMore() async {
    final after = _next;
    if (!hasMore.value || after == null || isLoadingMore.value) return;
    final seq = _seq;
    isLoadingMore.value = true;
    try {
      final page = await groups.colleagues(query: _query, after: after);
      if (seq != _seq) return;
      people.addAll(_withoutMembers(page.people));
      hasMore.value = page.hasMore;
      _next = page.next;
    } on SocketCallError catch (_) {
      hasMore.value = false;
    } finally {
      isLoadingMore.value = false;
    }
  }

  bool isSelected(ChatPerson p) =>
      selected.any((s) => s.username == p.username);

  void toggle(ChatPerson p) {
    if (isBusy) return;
    if (isSelected(p)) {
      selected.removeWhere((s) => s.username == p.username);
    } else {
      selected.add(p);
    }
  }

  // ---- creating --------------------------------------------------------------

  static const _needsConnection =
      'This needs a connection. Try again when you are online.';

  /// Create (or, for an existing group, add). Offline it does nothing but say
  /// so.
  Future<void> submit() async {
    if (!canSubmit || phase.value == NewGroupPhase.done) return;
    if (isOffline) {
      notice.value = _needsConnection;
      return;
    }
    notice.value = null;
    if (isAddingToExisting) {
      await _addAll(selected.toList());
    } else {
      await _create();
    }
  }

  Future<void> _create() async {
    final target = cleanName;
    phase.value = NewGroupPhase.creating;
    final result = await groups.create(target);
    switch (result.status) {
      case GroupCreateStatus.created:
        await _afterCreated(target);
      case GroupCreateStatus.refused:
        phase.value = NewGroupPhase.editing;
        notice.value = result.text;
      case GroupCreateStatus.offline:
        phase.value = NewGroupPhase.editing;
        notice.value = _needsConnection;
      case GroupCreateStatus.unconfirmed:
        // No cid on this command: never sent again by itself. The server's
        // own list says whether it went through.
        _createdName = target;
        phase.value = NewGroupPhase.unconfirmed;
        await checkCreated();
    }
  }

  Future<void> checkCreated() async {
    final target = _createdName;
    if (target == null || isChecking.value) return;
    isChecking.value = true;
    unconfirmedText.value = null;
    final isMine = await groups.isMyGroup(target);
    isChecking.value = false;
    if (isMine == true) {
      await _afterCreated(target);
    } else if (isMine == false) {
      _createdName = null;
      phase.value = NewGroupPhase.editing;
      notice.value = "The group wasn't created. You can create it again.";
    } else {
      unconfirmedText.value =
          "We couldn't tell whether the group was created. Check again when "
          'you are online.';
    }
  }

  Future<void> _afterCreated(String target) async {
    _createdName = target;
    if (selected.isEmpty) {
      await _open();
    } else {
      await _addAll(selected.toList());
    }
  }

  /// One `/addmember` at a time (the repository keeps them 400 ms apart), and
  /// on to the next person whatever the last one came to.
  Future<void> _addAll(List<ChatPerson> queue) async {
    phase.value = NewGroupPhase.adding;
    total.value = queue.length;
    progress.value = 0;
    final fresh = <GroupAddResult>[];
    for (final person in queue) {
      progress.value++;
      if (isOffline) {
        fresh.add(
          GroupAddResult(
            person,
            GroupAddStatus.failed,
            'Not sent: you went offline.',
          ),
        );
        continue;
      }
      fresh.add(await groups.addMember(groupName, person));
    }
    final redone = {for (final r in fresh) r.person.username};
    results.assignAll([
      ...results.where((r) => !redone.contains(r.person.username)),
      ...fresh,
    ]);
    phase.value = NewGroupPhase.done;
    if (results.every((r) => r.status == GroupAddStatus.added)) await _open();
  }

  /// Only the people who failed, once more.
  Future<void> retryFailed() async {
    if (isBusy) return;
    if (isOffline) {
      notice.value = _needsConnection;
      return;
    }
    notice.value = null;
    await _addAll([
      for (final r in results)
        if (r.status == GroupAddStatus.failed) r.person,
    ]);
  }

  int count(GroupAddStatus status) =>
      results.where((r) => r.status == status).length;

  /// "3 added, 1 invitation sent, 2 failed".
  String get summary {
    final added = count(GroupAddStatus.added);
    final invited = count(GroupAddStatus.invited);
    final failed = count(GroupAddStatus.failed);
    return [
      if (added > 0) '$added added',
      if (invited > 0)
        invited == 1 ? '1 invitation sent' : '$invited invitations sent',
      if (failed > 0) '$failed failed',
    ].join(', ');
  }

  Future<void> openGroup() => _open();

  Future<void> _open() async {
    if (SeedUi.isActive || isAddingToExisting) {
      Get.back<void>();
      return;
    }
    await Get.offNamed(AppRoutes.conversationOf('group:$groupName'));
  }

  // ---- sample states (SEED_UI) -----------------------------------------------

  void applySeed(String state) {
    SeedUi.newGroupOffline.value = state == 'offline';
    phase.value = NewGroupPhase.editing;
    results.clear();
    selected.clear();
    notice.value = null;
    final all = SeedUi.groupPeopleAll();
    ChatPerson who(String u) => all.firstWhere((x) => x.username == u);
    final String text;
    switch (state) {
      case 'name':
        text = 'Care Team';
      case 'prefix':
        text = 'Care';
      case 'partial':
        text = 'Launch Crew';
        selected.assignAll([
          who('priya'),
          who('meera'),
          who('arjun'),
          who('kavitha'),
        ]);
      case 'invite':
        text = 'Partners';
        selected.assignAll([who('priya'), who('ravi'), who('nina')]);
      default:
        text = '';
    }
    nameField.text = text;
    name.value = text;
    loadPeople();
  }

  @override
  void onClose() {
    AppNotices.hide(_lastNotice ?? '');
    _debounce?.cancel();
    nameField.dispose();
    queryField.dispose();
    super.onClose();
  }
}
