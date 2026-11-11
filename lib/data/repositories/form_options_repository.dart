import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../core/debug/seed_sample_forms.dart';
import '../../core/debug/seed_ui.dart';
import '../db/app_database.dart';
import '../models/form_option.dart';
import '../models/ids.dart';
import '../models/slot_day.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

/// One list `form.options` gave, as kept for a form, a field and the values of
/// the fields it depends on.
class KeptChoices {
  const KeptChoices({
    required this.reply,
    required this.etag,
    required this.cacheSec,
    required this.fetchedTs,
    required this.rev,
  });

  final Map<String, dynamic> reply;
  final String etag;
  final int cacheSec;
  final int fetchedTs;
  final String rev;

  FieldRows get rows => FieldRows.fromReply(reply);
}

/// What the forms button offers: `options.list` and `options.categories`,
/// cached per organisation and user for offline, plus the last forms used and
/// the choices of list fields that take them from the organisation.
class FormOptionsRepository extends GetxService {
  FormOptionsRepository(this._db, this._session, this._socket);

  static const recentCount = 3;

  /// How long a kept list is reused when the server gives no time (0), and how
  /// long one is still shown when the server can't be asked.
  static const defaultReuse = Duration(minutes: 5);
  static const staleLimit = Duration(days: 2);

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
  (String, String)? _lastScope;

  String? get _org => _session.orgId;
  String? get _me => _session.userId;

  @override
  void onInit() {
    super.onInit();
    ever(_session.current, (info) {
      _choices.clear();
      options.clear();
      categories.clear();
      recents.clear();
      isLoaded.value = false;
      hasError.value = false;
      final scope = info == null ? null : (info.orgId, info.userId);
      final last = _lastScope;
      // A different organisation or person: what was kept for the last one goes.
      if (scope != null && last != null && scope != last) {
        unawaited(clearScope(last.$1, last.$2));
      }
      if (scope != null) _lastScope = scope;
      unawaited(load());
    });
    _lastScope = _session.current.value == null
        ? null
        : (_session.current.value!.orgId, _session.current.value!.userId);
    _socket.events.listen((e) {
      if (e['type'] == 'sd_event' && e['event'] == 'options_changed') {
        unawaited(clearOrg());
      }
    });
    _socket.listenOnline('form options', refresh);
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

  // ---- choices of selection, fill and fetch fields ---------------------------

  /// The key of a kept list: the values of the fields it depends on, in a
  /// fixed order (a cascading list is another list for each parent value).
  static String cacheKey(Map<String, dynamic> values) {
    final names = values.keys.toList()..sort();
    return jsonEncode({for (final n in names) n: values[n]});
  }

  /// A kept list is reused for the server's `cacheSec`, or [defaultReuse]
  /// when that is 0.
  static bool isFresh(int fetchedTs, int cacheSec, int nowTs) {
    final reuse = cacheSec > 0 ? Duration(seconds: cacheSec) : defaultReuse;
    return nowTs - fetchedTs < reuse.inMilliseconds;
  }

  /// With no connection, a kept list is still shown for [staleLimit].
  static bool isUsableOffline(int fetchedTs, int nowTs) =>
      nowTs - fetchedTs <= staleLimit.inMilliseconds;

  /// What a field that reads a source offers now (`form.options`), given the
  /// values of the fields its parameters come from. A kept list is used while
  /// it is fresh, checked again with its etag when it is not, and shown
  /// marked as old when the server can't be reached. Null when it can't be
  /// had (nothing usable kept and no connection, or the server refused).
  Future<FieldRows?> fieldRows({
    required String form,
    required String scope,
    required String field,
    required Map<String, dynamic> values,
    int limit = 500,
    String rev = '',
  }) async {
    if (SeedUi.isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return SeedSampleForms.fieldRows(form, field, values);
    }
    final org = _org;
    final user = _me;
    final key = cacheKey(values);
    final kept = org == null || user == null
        ? null
        : await keptFor(org, user, form, field, key, rev);
    final now = DateTime.now().millisecondsSinceEpoch;
    FieldRows? offline() => kept != null && isUsableOffline(kept.fetchedTs, now)
        ? kept.rows.asStale()
        : null;
    if (!_socket.isOnline) return offline();
    if (kept != null && isFresh(kept.fetchedTs, kept.cacheSec, now)) {
      return kept.rows;
    }
    try {
      final data = await _socket.sdCall('form.options', {
        'tstruct': form,
        'scope': scope == 'user' ? 'user' : 'admin',
        'field': field,
        'values': values,
        'limit': limit,
        if (kept != null && kept.etag.isNotEmpty) 'ifNoneMatch': kept.etag,
      }, timeout: const Duration(seconds: 30));
      if (data['notModified'] == true) {
        if (kept == null || org == null || user == null) return null;
        await _db.update(
          'UPDATE form_choice_cache SET fetched_ts = ?, cache_sec = ? '
          'WHERE org_id = ? AND user_id = ? AND form = ? AND field = ? AND cache_key = ?',
          [
            DateTime.now().millisecondsSinceEpoch,
            data['cacheSec'] == null ? kept.cacheSec : intOf(data['cacheSec']),
            org,
            user,
            form,
            field,
            key,
          ],
        );
        return kept.rows;
      }
      final rows = FieldRows.fromReply(data);
      if (!rows.isWaiting && org != null && user != null) {
        await keepChoices(
          org,
          user,
          form,
          field,
          key,
          {
            'options': data['options'],
            'rows': data['rows'],
            'columns': data['columns'],
            'truncated': data['truncated'],
          },
          etag: idText(data['etag']),
          cacheSec: intOf(data['cacheSec']),
          rev: rev,
        );
      }
      return rows;
    } on SocketCallError catch (e) {
      return e.isConnectionGap ? offline() : null;
    }
  }

  Future<void> keepChoices(
    String org,
    String user,
    String form,
    String field,
    String key,
    Map<String, dynamic> reply, {
    String etag = '',
    int cacheSec = 0,
    String rev = '',
    int? fetchedTs,
  }) => _db.insert(
    'INSERT OR REPLACE INTO form_choice_cache(org_id, user_id, form, field, cache_key, reply_json, etag, cache_sec, fetched_ts, rev) '
    'VALUES(?,?,?,?,?,?,?,?,?,?)',
    [
      org,
      user,
      form,
      field,
      key,
      jsonEncode(reply),
      etag,
      cacheSec,
      fetchedTs ?? DateTime.now().millisecondsSinceEpoch,
      rev,
    ],
  );

  Future<KeptChoices?> keptFor(
    String org,
    String user,
    String form,
    String field,
    String key,
    String rev,
  ) async {
    final rows = await _db.query(
      'SELECT reply_json, etag, cache_sec, fetched_ts, rev FROM form_choice_cache '
      'WHERE org_id = ? AND user_id = ? AND form = ? AND field = ? AND cache_key = ?',
      [org, user, form, field, key],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    // Kept for another version of the form: gone.
    if (idText(r['rev']) != rev) {
      await _db.update(
        'DELETE FROM form_choice_cache WHERE org_id = ? AND user_id = ? AND form = ? AND field = ? AND cache_key = ?',
        [org, user, form, field, key],
      );
      return null;
    }
    try {
      final reply = (jsonDecode(idText(r['reply_json'])) as Map)
          .cast<String, dynamic>();
      return KeptChoices(
        reply: reply,
        etag: idText(r['etag']),
        cacheSec: intOf(r['cache_sec']),
        fetchedTs: intOf(r['fetched_ts']),
        rev: rev,
      );
    } on Object {
      return null;
    }
  }

  /// The server refused a choice of this field: every list kept for it goes.
  Future<void> dropField(
    String form,
    String field, {
    String? org,
    String? user,
  }) async {
    final o = org ?? _org;
    final u = user ?? _me;
    if (o == null || u == null) return;
    await _db.update(
      'DELETE FROM form_choice_cache WHERE org_id = ? AND user_id = ? AND form = ? AND field = ?',
      [o, u, form, field],
    );
  }

  /// Everything kept for one form (its rev changed).
  Future<void> dropForm(String form, {String? org, String? user}) async {
    final o = org ?? _org;
    final u = user ?? _me;
    if (o == null || u == null) return;
    await _db.update(
      'DELETE FROM form_choice_cache WHERE org_id = ? AND user_id = ? AND form = ?',
      [o, u, form],
    );
  }

  /// `options_changed`: every kept list of the organisation.
  Future<void> clearOrg({String? org}) async {
    final o = org ?? _org;
    _choices.clear();
    if (o == null) return;
    await _db.update('DELETE FROM form_choice_cache WHERE org_id = ?', [o]);
  }

  Future<void> clearScope(String org, String user) => _db.update(
    'DELETE FROM form_choice_cache WHERE org_id = ? AND user_id = ?',
    [org, user],
  );

  /// The days and times a person can be booked (`avail.slots`), or null when
  /// they can't be had now.
  Future<List<SlotDay>?> slots(String user) async {
    if (SeedUi.isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return SeedSampleForms.slotDays();
    }
    if (!_socket.isOnline) return null;
    try {
      final data = await _socket.sdCall('avail.slots', {
        'user': user,
        'days': 14,
      }, timeout: const Duration(seconds: 30));
      final days = data['days'];
      if (days is! List) return const [];
      return [
        for (final d in days)
          if (d is Map && idText(d['date']).isNotEmpty)
            SlotDay(idText(d['date']), [
              for (final t in (d['slots'] as List? ?? const []))
                if (t is Map && idText(t['time']).isNotEmpty)
                  SlotTime(idText(t['time']), t['free'] == true),
            ]),
      ];
    } on SocketCallError catch (_) {
      return null;
    }
  }
}
