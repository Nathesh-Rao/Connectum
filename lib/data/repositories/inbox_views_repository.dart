import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../features/inbox/models/inbox_saved_view.dart';
import '../records/record_commands.dart';
import '../session_store.dart';

/// The Inbox's saved views (`inbox.views.get` / `save` / `delete` /
/// `default`). Memory only. Every command goes through the shared
/// [ReadGate]. The server keeps one document per person and each save
/// rewrites all of it, so every save and delete first reads the list again
/// and checks against that fresh list. A late answer of an older read never
/// wins. Failures keep the server's message ([SocketCallError.message]) or
/// say what the phone refused ([InboxViewError]).
class InboxViewsRepository extends GetxService {
  InboxViewsRepository(this._socket, this._store, this._gate);

  final SocketService _socket;
  final SessionStore _store;
  final ReadGate _gate;

  static const _timeout = Duration(seconds: 15);

  /// The last list that was read (or answered by a save).
  final views = <InboxSavedView>[].obs;

  /// The name the Inbox opens on when there is no "Default View".
  final defaultName = Rxn<String>();

  /// The list was read at least once for this person.
  final isReady = false.obs;

  /// The newest read failed; [views] is what was known before.
  final hasError = false.obs;

  int _seq = 0;

  @override
  void onInit() {
    super.onInit();
    ever(_store.current, (_) => reset());
  }

  /// Another person or organisation: nothing of the last one stays.
  void reset() {
    _seq++;
    views.clear();
    defaultName.value = null;
    isReady.value = false;
    hasError.value = false;
  }

  bool get isOnline => _socket.isOnline;

  /// The text to show for a failed call: the server's own words when it gave
  /// some, else [fallback].
  static String messageOf(Object e, String fallback) {
    final text = switch (e) {
      InboxViewError() => e.message,
      SocketCallError() => e.message,
      _ => '',
    };
    return text.trim().isEmpty ? fallback : text.trim();
  }

  /// Reads the list. Null when a newer call replaced it; throws
  /// [SocketCallError] when it failed (the old list stays).
  Future<InboxViewList?> load() async {
    final seq = ++_seq;
    try {
      final list = await _fetch();
      if (seq != _seq) return null;
      _take(list);
      hasError.value = false;
      return list;
    } on SocketCallError {
      if (seq == _seq) hasError.value = true;
      rethrow;
    }
  }

  /// Saves [setup] under [name] after reading the list again. [isNew] is
  /// Save as new / Create view (the name rules of a new view); [isDefault]
  /// also makes it the view the Inbox opens on. Returns the answered list.
  Future<InboxViewList> save(
    String name,
    Map<String, dynamic> setup, {
    bool isNew = false,
    bool isDefault = false,
  }) async {
    final fresh = await _fresh();
    final problem = InboxViewRules.problem(name, fresh.views, isNew: isNew);
    if (problem.isNotEmpty) throw InboxViewError(problem);
    return _write(RecordCmd.viewsSave, {
      'name': name,
      'view': setup,
      if (isDefault) 'default': true,
    });
  }

  /// Removes [name] after reading the list again (a view another device
  /// already removed is simply gone).
  Future<InboxViewList> delete(String name) async {
    final fresh = await _fresh();
    if (fresh.named(name) == null) return fresh;
    return _write(RecordCmd.viewsDelete, {'name': name});
  }

  /// Makes [name] the view the Inbox opens on, or none with null.
  Future<InboxViewList> setDefault(String? name) =>
      _write(RecordCmd.viewsDefault, {'name': name});

  // ---- calls -----------------------------------------------------------------

  Future<InboxViewList> _fresh() async {
    _seq++;
    final list = await _fetch();
    _take(list);
    hasError.value = false;
    return list;
  }

  Future<InboxViewList> _fetch() async {
    final data = await _call(RecordCmd.viewsGet, const {});
    return InboxViewList.tryParse(data) ??
        (throw const SocketCallError('parse'));
  }

  Future<InboxViewList> _write(String cmd, Map<String, dynamic> args) async {
    final data = await _call(cmd, args);
    _seq++;
    final answered = InboxViewList.tryParse(data);
    final list = answered ?? await _fetch();
    _take(list);
    hasError.value = false;
    return list;
  }

  Future<Map<String, dynamic>> _call(
    String cmd,
    Map<String, dynamic> args,
  ) async {
    try {
      if (!_socket.isOnline) throw const SocketCallError('not_connected');
      return await _gate.run(
        () => _socket.sdCall(cmd, args, timeout: _timeout),
      );
    } on SocketCallError catch (e) {
      AppLog.w(
        'inbox_views_repository',
        '$cmd failed code=${e.code} message=${e.message}',
      );
      rethrow;
    }
  }

  void _take(InboxViewList list) {
    views.assignAll(list.views);
    defaultName.value = list.defaultName;
    isReady.value = true;
  }
}
