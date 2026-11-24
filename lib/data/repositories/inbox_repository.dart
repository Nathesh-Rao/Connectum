import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../features/inbox/models/inbox_page.dart';
import '../../features/inbox/models/inbox_query.dart';
import '../models/ids.dart';
import '../records/record_commands.dart';
import '../session_store.dart';
import '../socket/read_gate.dart';
import '../socket/socket_service.dart';

/// One kind of read with its own sequence counter, the last good answer and
/// the error flag. Only the newest ask's answer is delivered; an older one is
/// dropped when it lands. A failed read keeps [last] and sets [hasError].
class InboxRead<T> {
  /// The last answer that was read successfully (the offline bar shows it).
  final last = Rxn<T>();

  /// The newest ask failed; [last] is what was there before.
  final hasError = false.obs;

  int _seq = 0;

  void _reset() {
    _seq++;
    last.value = null;
    hasError.value = false;
  }
}

/// The Inbox's reads: `records.query` pages, `records.counts`,
/// `records.people` and `people.cards`. Memory only, nothing in SQLite. Every
/// command goes through the shared [ReadGate]. A read returns null when a
/// newer ask of the same kind replaced it, and throws [SocketCallError] (or
/// [InboxQueryError] for an ask that breaks a server limit) when it failed.
class InboxRepository extends GetxService {
  InboxRepository(this._socket, this._store, this._gate);

  final SocketService _socket;
  final SessionStore _store;
  final ReadGate _gate;

  static const _timeout = Duration(seconds: 30);

  final list = InboxRead<InboxPage>();
  final counts = InboxRead<InboxCounts>();
  final people = InboxRead<InboxPeople>();

  /// The filter panel's lists (`records.query` with `facets:true`).
  final facets = InboxRead<InboxFacets>();

  final _cards = <String, PersonCard>{};
  final _asked = <String>{};

  /// Bumps when cards were learned, so a card showing a name rebuilds.
  final cardRevision = 0.obs;

  @override
  void onInit() {
    super.onInit();
    ever(_store.current, (_) => reset());
  }

  /// Another person or organisation: nothing of the last one stays and every
  /// read in flight is dropped when it lands.
  void reset() {
    list._reset();
    counts._reset();
    people._reset();
    facets._reset();
    _cards.clear();
    _asked.clear();
    cardRevision.value++;
  }

  // ---- reads -----------------------------------------------------------------

  /// One page of `records.query` (50 rows by default). At [offset] 0 the
  /// answer replaces the list; further pages are added to it, each record
  /// once. Returns the whole list read so far, or null when dropped.
  Future<InboxPage?> query(
    InboxQuery q, {
    int offset = 0,
    int limit = RecordLimits.queryPageSize,
  }) async {
    final args = q.toArgs(limit: limit, offset: offset);
    return _read(
      list,
      RecordCmd.query,
      args,
      InboxPage.parse,
      merge: (prev, page) =>
          offset > 0 && prev != null && prev.received == offset
          ? prev.append(page)
          : page,
    );
  }

  /// What the filter panel's lists offer under [q] (`facets:true`, limit 1,
  /// offset 0); null when a newer ask replaced it.
  Future<InboxFacets?> queryFacets(InboxQuery q) async =>
      _read(facets, RecordCmd.query, q.toArgs(limit: 1), InboxFacets.parse);

  /// `records.counts`; null when dropped. An answer without me, team and all
  /// as numbers is a failed read (the screen then counts what it holds).
  Future<InboxCounts?> loadCounts() => _read(
    counts,
    RecordCmd.counts,
    const {},
    (data) =>
        InboxCounts.tryParse(data) ?? (throw const SocketCallError('parse')),
  );

  /// `records.people`; null when dropped.
  Future<InboxPeople?> loadPeople() =>
      _read(people, RecordCmd.queryPeople, const {}, InboxPeople.parse);

  Future<T?> _read<T>(
    InboxRead<T> r,
    String cmd,
    Map<String, dynamic> args,
    T Function(Map<String, dynamic>) parse, {
    T Function(T? previous, T next)? merge,
  }) async {
    final seq = ++r._seq;
    try {
      if (!_socket.isOnline) throw const SocketCallError('not_connected');
      final data = await _gate.run(
        () => _socket.sdCall(cmd, args, timeout: _timeout),
      );
      if (seq != r._seq) return null;
      final value = parse(data);
      r.last.value = merge == null ? value : merge(r.last.value, value);
      r.hasError.value = false;
      return r.last.value;
    } on SocketCallError catch (e) {
      AppLog.w(
        'inbox_repository',
        '$cmd failed code=${e.code} message=${e.message}',
      );
      if (seq != r._seq) return null;
      r.hasError.value = true;
      rethrow;
    } catch (e, st) {
      AppLog.e('inbox_repository', e, st, '$cmd unreadable');
      if (seq != r._seq) return null;
      r.hasError.value = true;
      throw const SocketCallError('parse');
    }
  }

  // ---- people ----------------------------------------------------------------

  /// What is known about [username] (any case), or null.
  PersonCard? cardOf(String username) => _cards[username.trim().toLowerCase()];

  /// Learns the people in [usernames] that are not known yet, in batches of
  /// at most 60, one batch at a time. A name is asked once; a failed batch
  /// is forgotten so a later call asks again. Answers are facts about
  /// people, so every one is kept even when a newer call began meanwhile.
  Future<void> loadCards(Iterable<String> usernames) async {
    final unknown =
        <String>{
            for (final u in usernames)
              if (u.trim().isNotEmpty) u.trim().toLowerCase(),
          }.where((u) => !_cards.containsKey(u) && !_asked.contains(u)).toList()
          ..sort();
    for (var i = 0; i < unknown.length; i += RecordLimits.peopleCardsBatch) {
      final batch = unknown.sublist(
        i,
        (i + RecordLimits.peopleCardsBatch).clamp(0, unknown.length),
      );
      _asked.addAll(batch);
      try {
        if (!_socket.isOnline) throw const SocketCallError('not_connected');
        final data = await _gate.run(
          () => _socket.sdCall(RecordCmd.peopleCards, {
            'usernames': batch,
          }, timeout: _timeout),
        );
        final raw = data['people'];
        if (raw is Map) {
          for (final e in raw.entries) {
            final card = PersonCard.tryParse(
              idText(e.key).toLowerCase(),
              e.value,
            );
            if (card != null) _cards[card.username] = card;
          }
        }
        cardRevision.value++;
      } on SocketCallError catch (e) {
        AppLog.w(
          'inbox_repository',
          '${RecordCmd.peopleCards} failed code=${e.code} message=${e.message}',
        );
        _asked.removeAll(batch);
        return;
      } catch (e, st) {
        AppLog.e(
          'inbox_repository',
          e,
          st,
          '${RecordCmd.peopleCards} unreadable',
        );
      }
    }
  }
}
