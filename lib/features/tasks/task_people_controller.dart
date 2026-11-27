import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_tasks.dart';
import '../../core/debug/seed_tickets.dart';
import 'package:connectum/core/log/log.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../chats/models/chat_person.dart';
import 'tasks_texts.dart';

/// The people list of the assignee and "send to" sheets: the colleagues
/// list (`users.colleagues`), searched by name. Made by the Tasks controller
/// for one sheet; [close] when the sheet closes.
class TaskPeopleController {
  TaskPeopleController(this._people, {this.source});

  final GroupRepository? _people;

  /// Where the names come from instead of the colleagues list (the people a
  /// record can be sent to). One page; typing is debounced here.
  final Future<GroupPeoplePage> Function(String q)? source;

  final query = TextEditingController();
  final people = <ChatPerson>[].obs;
  final isLoading = true.obs;
  final isLoadingMore = false.obs;
  final hasMore = false.obs;
  final error = RxnString();

  Timer? _debounce;
  String? _next;
  int _seq = 0;

  Future<void> load() async {
    final seq = ++_seq;
    isLoading.value = true;
    error.value = null;
    try {
      final page = await _fetch(query.text.trim(), null);
      if (seq != _seq) return;
      people.assignAll(page.people);
      hasMore.value = page.hasMore;
      _next = page.next;
    } on SocketCallError catch (e) {
      if (seq != _seq) return;
      error.value = e.message.isEmpty ? TasksTexts.pickerError : e.message;
    } finally {
      if (seq == _seq) isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value || _next == null) return;
    final seq = _seq;
    isLoadingMore.value = true;
    try {
      final page = await _fetch(query.text.trim(), _next);
      if (seq != _seq) return;
      people.addAll(page.people);
      hasMore.value = page.hasMore;
      _next = page.next;
    } on SocketCallError catch (e) {
      AppLog.w('task_people_controller', 'socket ${e.code}');
      hasMore.value = false;
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<GroupPeoplePage> _fetch(String q, String? after) async {
    final custom = source;
    if (custom != null) return custom(q);
    if (SeedTasks.isActive || SeedTickets.isActive) {
      final all = [
        for (final p in SeedTasks.people)
          if (q.isEmpty || p.name.toLowerCase().contains(q.toLowerCase())) p,
      ];
      return GroupPeoplePage(all, hasMore: false);
    }
    return _people!.colleagues(query: q, after: after);
  }

  void onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), load);
  }

  /// The sheet closed: no search is left waiting.
  void close() {
    _debounce?.cancel();
    query.dispose();
  }
}
