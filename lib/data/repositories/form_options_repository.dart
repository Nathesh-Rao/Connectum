import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../db/app_database.dart';
import '../models/form_option.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

/// What the forms button offers: `options.list` and `options.categories`,
/// cached per organisation and user for offline, plus the last forms used and
/// the choices of list fields that take them from the organisation.
class FormOptionsRepository extends GetxService {
  FormOptionsRepository(this._db, this._session, this._socket);

  static const recentCount = 3;

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;

  final options = <FormOption>[].obs;
  final categories = <String, FormCategory>{}.obs;
  final recents = <FormRecent>[].obs;
  final isLoaded = false.obs;
  final hasError = false.obs;

  final _choices = <String, List<FormChoice>>{};
  bool _isFetching = false;

  String? get _org => _session.orgId;
  String? get _me => _session.userId;

  @override
  void onInit() {
    super.onInit();
    ever(_session.current, (_) {
      _choices.clear();
      unawaited(load());
    });
    _socket.onOnline.listen((_) => unawaited(refresh()));
    unawaited(load());
  }

  /// Reads the cache, then refreshes it when online.
  Future<void> load() async {
    if (SeedUi.isActive) {
      options.assignAll(SeedUi.formOptions());
      categories.assignAll(SeedUi.formCategories());
      recents.assignAll(SeedUi.recents);
      isLoaded.value = true;
      return;
    }
    final org = _org;
    final user = _me;
    if (org == null || user == null) {
      options.clear();
      recents.clear();
      isLoaded.value = false;
      return;
    }
    final rows = await _db.query(
      'SELECT options_json, categories_json FROM form_options WHERE org_id = ? AND user_id = ?',
      [org, user],
    );
    if (rows.isNotEmpty) _apply(rows.first);
    await _loadRecents();
    isLoaded.value = rows.isNotEmpty;
    if (_socket.isOnline) await refresh();
  }

  void _apply(Map<String, Object?> row) {
    try {
      final list = jsonDecode(idText(row['options_json'])) as List;
      options.assignAll([for (final o in list) FormOption.fromMap(o as Map)]);
      final cats = jsonDecode(idText(row['categories_json'])) as List;
      categories.assignAll({
        for (final c in cats) idText((c as Map)['id']): FormCategory.fromMap(c),
      });
    } on Object {
      options.clear();
    }
  }

  /// Fetches both lists and keeps them. A failure leaves the cache as it was
  /// and sets [hasError] only when there is nothing cached to show.
  Future<void> refresh() async {
    if (SeedUi.isActive || _isFetching || !_socket.isOnline) return;
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    _isFetching = true;
    try {
      final listed = await _socket.sdCall('options.list', {});
      final cats = await _socket.sdCall('options.categories', {
        'includeEmpty': true,
      });
      final list = [
        for (final o in (listed['options'] as List? ?? const []))
          if (o is Map) FormOption.fromMap(o),
      ]..sort((a, b) => a.order.compareTo(b.order));
      final categoryList = (cats['categories'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      await _db.insert(
        'INSERT OR REPLACE INTO form_options(org_id, user_id, options_json, categories_json, fetched_ts) VALUES(?,?,?,?,?)',
        [
          org,
          user,
          jsonEncode([for (final o in list) o.toMap()]),
          jsonEncode([
            for (final c in categoryList) FormCategory.fromMap(c).toMap(),
          ]),
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      options.assignAll(list);
      categories.assignAll({
        for (final c in categoryList) idText(c['id']): FormCategory.fromMap(c),
      });
      hasError.value = false;
      isLoaded.value = true;
    } on SocketCallError catch (_) {
      hasError.value = options.isEmpty;
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _loadRecents() async {
    final rows = await _db.query(
      'SELECT name, scope, caption FROM form_recents WHERE org_id = ? AND user_id = ? '
      'ORDER BY used_ts DESC LIMIT $recentCount',
      [_org, _me],
    );
    recents.assignAll([
      for (final r in rows)
        FormRecent(
          name: idText(r['name']),
          scope: idText(r['scope']),
          caption: idText(r['caption']),
        ),
    ]);
  }

  /// A form was opened: it moves to the front of Recent.
  Future<void> markUsed(String name, String scope, String caption) async {
    if (SeedUi.isActive) {
      SeedUi.recents
        ..removeWhere((r) => r.name == name)
        ..insert(0, FormRecent(name: name, scope: scope, caption: caption));
      if (SeedUi.recents.length > recentCount) {
        SeedUi.recents.removeRange(recentCount, SeedUi.recents.length);
      }
      recents.assignAll(SeedUi.recents);
      return;
    }
    if (_org == null || _me == null) return;
    await _db.insert(
      'INSERT OR REPLACE INTO form_recents(org_id, user_id, name, scope, caption, used_ts) VALUES(?,?,?,?,?,?)',
      [_org, _me, name, scope, caption, DateTime.now().millisecondsSinceEpoch],
    );
    await _db.update(
      'DELETE FROM form_recents WHERE org_id = ? AND user_id = ? AND name NOT IN ('
      'SELECT name FROM form_recents WHERE org_id = ? AND user_id = ? ORDER BY used_ts DESC LIMIT $recentCount)',
      [_org, _me, _org, _me],
    );
    await _loadRecents();
  }

  // ---- choices of list fields -----------------------------------------------

  /// The choices a list field takes from the organisation (`branches`,
  /// `users`, `isource:<name>`...), or null when they can't be had now (no
  /// connection and none fetched yet).
  Future<List<FormChoice>?> choicesFor(String source) async {
    if (SeedUi.isActive) return SeedUi.choices(source);
    final cached = _choices[source];
    if (cached != null) return cached;
    if (!_socket.isOnline) return null;
    try {
      final list = await _fetchChoices(source);
      if (list != null) _choices[source] = list;
      return list;
    } on SocketCallError catch (_) {
      return null;
    }
  }

  Future<List<FormChoice>?> _fetchChoices(String source) async {
    if (source.startsWith('isource:')) {
      final data = await _socket.sdCall('isource.values', {
        'key': source.substring('isource:'.length),
      });
      return _toChoices(data['values'] ?? data['items'] ?? data['list']);
    }
    if (source == 'users' || source == 'people') {
      final data = await _socket.sdCall('users.search', {'q': ''});
      final users = data['users'] ?? data['hits'] ?? data['list'];
      if (users is! List) return const [];
      return [
        for (final u in users)
          if (u is Map && idText(u['username']).isNotEmpty)
            FormChoice(
              idText(u['username']),
              idText(u['name']).isEmpty
                  ? idText(u['username'])
                  : idText(u['name']),
            ),
      ];
    }
    final data = await _socket.sdCall('cfg.lookups', {});
    final raw = data[source];
    if (raw == null) return null;
    return _toChoices(raw);
  }

  static List<FormChoice> _toChoices(Object? raw) {
    if (raw is! List) return const [];
    final out = <FormChoice>[];
    for (final v in raw) {
      if (v is Map) {
        final value = idText(v['value'] ?? v['name'] ?? v['id']);
        if (value.isEmpty) continue;
        final label = idText(v['label'] ?? v['caption'] ?? v['name']);
        out.add(FormChoice(value, label.isEmpty ? value : label));
      } else if (idText(v).isNotEmpty) {
        out.add(FormChoice(idText(v), idText(v)));
      }
    }
    return out;
  }
}
