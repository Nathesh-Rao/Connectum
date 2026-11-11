import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_tickets.dart';
import '../models/ticket.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';

/// The `status.*` calls and the ticket events. A ticket is a form record with
/// a status field; nothing here looks at a form's name. Nothing is kept but
/// the badge number and the last tickets read (so a detail opens at once);
/// the screens own their lists and read again when [refreshes] fires
/// (reconnect, resume, any ticket event, coalesced), because events sent
/// while offline are lost.
class TicketRepository extends GetxService with WidgetsBindingObserver {
  TicketRepository(this._socket, this._store, this._conversations);

  final SocketService _socket;
  final SessionStore _store;
  final ConversationRepository _conversations;

  static const pageSize = 100;
  static const burst = Duration(milliseconds: 150);

  /// How many tickets are with this person now (the badge).
  final withTotal = 0.obs;

  final _refreshes = StreamController<void>.broadcast();
  final _assigned = StreamController<TicketAssigned>.broadcast();
  final _known = <int, Ticket>{};
  final _names = <String, String>{};
  Timer? _burst;
  StreamSubscription<Map<String, dynamic>>? _events;
  StreamSubscription<void>? _online;

  /// Read the first pages and the open ticket again.
  Stream<void> get refreshes => _refreshes.stream;

  /// A ticket is now with this person (also when it was raised to them).
  Stream<TicketAssigned> get assigned => _assigned.stream;

  String get me => (SeedTickets.isActive ? SeedTickets.me : _store.userId ?? '')
      .toLowerCase();

  bool isMe(String user) => user.isNotEmpty && user.toLowerCase() == me;

  /// The last read of ticket [id], if any.
  Ticket? known(int id) => _known[id];

  /// Changes whenever a known ticket changes, so a card reading it rebuilds.
  final cardRevision = 0.obs;
  static const cardTtl = Duration(seconds: 60);
  final _extras = <int, ({bool isAdmin, bool? inPool})>{};
  final _readAt = <int, DateTime>{};
  final _reading = <int, Future<void>>{};

  /// What a chat card needs to work out its actions, from the last read.
  /// Reading [cardRevision] first makes an `Obx` follow it.
  ({Ticket ticket, bool isAdmin, bool? inPool})? stateOf(int id) {
    cardRevision.value;
    final t = _known[id];
    if (t == null) return null;
    final extra = _extras[id];
    return (ticket: t, isAdmin: extra?.isAdmin ?? false, inPool: extra?.inPool);
  }

  /// Reads ticket [id] for a card when the last read is older than
  /// [cardTtl] or a ticket event made it stale. One read per ticket at a
  /// time; a refused or failed read is not repeated until the same moment.
  Future<void> ensure(int id) {
    final at = _readAt[id];
    if (at != null && DateTime.now().difference(at) < cardTtl) {
      return Future.value();
    }
    return _reading[id] ??= _readForCard(id).whenComplete(() {
      _reading.remove(id);
    });
  }

  Future<void> _readForCard(int id) async {
    try {
      await get(id);
    } on SocketCallError {
      // The card keeps what it has (or shows no actions).
    }
    _readAt[id] = DateTime.now();
  }

  /// A person's display name when it is known, else the username.
  String nameOf(String user) {
    if (user.isEmpty) return user;
    final saved = _names[user.toLowerCase()];
    if (saved != null) return saved;
    final dm = 'dm:${user.toLowerCase()}';
    for (final c in _conversations.conversations) {
      if (c.convId.toLowerCase() == dm && c.title.trim().isNotEmpty) {
        return c.title;
      }
    }
    return user;
  }

  /// Remembers a name seen in a picker.
  void rememberName(String user, String name) {
    if (user.isNotEmpty && name.trim().isNotEmpty) {
      _names[user.toLowerCase()] = name;
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _events = _socket.events.listen(onEvent);
    _online = _socket.onOnline.listen((_) => scheduleRefresh());
    ever(_store.current, (_) => _reset());
  }

  /// Another person or organisation: nothing of the last one stays.
  void _reset() {
    _burst?.cancel();
    _known.clear();
    _extras.clear();
    _readAt.clear();
    _names.clear();
    withTotal.value = 0;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _burst?.cancel();
    _events?.cancel();
    _online?.cancel();
    _refreshes.close();
    _assigned.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleRefresh();
  }

  /// Bursts of events become one read.
  void scheduleRefresh() {
    _burst?.cancel();
    _burst = Timer(burst, () {
      _readAt.clear();
      cardRevision.value++;
      if (!_refreshes.isClosed) _refreshes.add(null);
    });
  }

  /// Public so the debug page and tests can feed it events.
  void onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event') return;
    final event = e['event'];
    if (event != 'ticket_assigned' && event != 'submissions_changed') return;
    if (event == 'ticket_assigned') {
      final data = e['data'];
      final assigned = TicketAssigned.tryParse(data is Map ? data : e);
      if (assigned != null && !_assigned.isClosed) _assigned.add(assigned);
    }
    scheduleRefresh();
  }

  // ---- calls -----------------------------------------------------------------

  /// [as]: with | raised. [offset]: how many rows the screen already holds.
  Future<TicketPage> mine({required String as, int offset = 0}) async {
    final Map<String, dynamic> data;
    if (SeedTickets.isActive) {
      data = SeedTickets.mine(as, offset, pageSize);
    } else {
      data = await _socket.sdCall('status.mine', {
        'as': as,
        'limit': pageSize,
        if (offset > 0) 'offset': offset,
      });
    }
    final page = TicketPage.parse(data);
    for (final t in page.tickets) {
      _known[t.id] = t;
    }
    if (page.tickets.isNotEmpty) cardRevision.value++;
    if (as == 'with') withTotal.value = page.total;
    return page;
  }

  /// One ticket with its status table. Throws [SocketCallError] when the
  /// server refuses; a record that has no status table is returned too, and
  /// its `isTicket` is false.
  Future<TicketDetail> get(int id) async {
    final Map<String, dynamic> data;
    if (SeedTickets.isActive) {
      data = SeedTickets.get(id);
    } else {
      data = await _socket.sdCall('status.get', {'id': id});
    }
    final detail =
        TicketDetail.tryParse(data) ??
        (throw const SocketCallError('error', 'The server sent no ticket.'));
    _known[id] = detail.ticket;
    _extras[id] = (isAdmin: detail.isAdmin, inPool: detail.inPool);
    cardRevision.value++;
    return detail;
  }

  /// Oldest first.
  Future<List<TicketHistoryEntry>> history(int id) async {
    final Map<String, dynamic> data;
    if (SeedTickets.isActive) {
      data = SeedTickets.history(id);
    } else {
      data = await _socket.sdCall('status.history', {'id': id});
    }
    return TicketHistoryEntry.parseAll(data);
  }

  /// One update. [payload] is built by `TicketPayload`. Sent once; a retry
  /// of a lost answer carries the same `requestId`.
  Future<TicketUpdateResult> update(Map<String, dynamic> payload) async {
    final Map<String, dynamic> data;
    if (SeedTickets.isActive) {
      data = SeedTickets.update(payload);
    } else {
      data = await _socket.sdCall('status.update', payload);
    }
    return TicketUpdateResult.parse(data);
  }
}
