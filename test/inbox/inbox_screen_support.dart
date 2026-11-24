import 'dart:async';

import 'package:connectum/data/repositories/inbox_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'inbox_support.dart';

class FakeShell extends Fake implements HomeShellController {
  @override
  final tab = HomeTab.inbox.obs;
}

typedef Route = FutureOr<Map<String, dynamic>> Function(
  Map<String, dynamic> args,
);

/// A record as `records.query` sends it.
Map<String, dynamic> record(
  int id, {
  String form = 't',
  String holder = 'ana',
  String by = 'rhea',
  String? status,
  Map<String, dynamic>? values,
  Map<String, dynamic>? labels,
}) => {
  'id': id,
  'tstruct': form,
  'by': by,
  'holder': holder,
  'ts': 1764000000000 + id,
  'status': ?status,
  'values': values ?? {'title': 'Record $id'},
  'labels': ?labels,
};

/// The `structures` of the replies below.
const structures = {
  't': {
    'caption': 'Thing',
    'fields': {'title': 'Title', 'stage': 'Stage', 'priority': 'Priority'},
    'status': {
      'field': 'stage',
      'final': ['Done'],
    },
  },
};

Map<String, dynamic> queryReply(
  List<Map<String, dynamic>> rows, {
  int? total,
  bool hasMore = false,
  bool capped = false,
}) => {
  'submissions': rows,
  'structures': structures,
  'total': total ?? rows.length,
  'hasMore': hasMore,
  'capped': capped,
};

Map<String, dynamic> countsReply({int reports = 0}) => {
  'me': 3,
  'team': 5,
  'all': 8,
  'reports': reports,
  'cap': 1000,
};

class RigConnectivity extends FakeConnectivity {
  void set(AppConnectivity s) => state.value = s;
}

/// The Inbox controller on a socket whose answers the test scripts by action.
class InboxRig {
  InboxRig({String user = 'ana', bool isOnline = true}) {
    clock = GateClock();
    socket = HeldSocket();
    if (isOnline) socket.goOnline();
    store = FakeStore(user: user);
    inbox = InboxRepository(
      socket,
      store,
      ReadGate(now: clock.read, delay: clock.delay),
    )..onInit();
    tickets = TicketRepository(socket, store, FakeConversations());
    connectivity = RigConnectivity()
      ..set(isOnline ? AppConnectivity.online : AppConnectivity.offline);
    shell = FakeShell();
    socket.handler = (action, args) async {
      final r = routes[action];
      if (r == null) throw const SocketCallError('not_found');
      return r(args);
    };
    routes['records.counts'] = (_) => countsReply();
    routes['people.cards'] = (_) => {'people': <String, dynamic>{}};
    controller = InboxController(
      inbox: inbox,
      tickets: tickets,
      store: store,
      connectivity: connectivity,
      shell: shell,
      newTicketDetail: (id) => throw UnimplementedError('no detail in tests'),
    );
  }

  late final GateClock clock;
  late final HeldSocket socket;
  late final FakeStore store;
  late final InboxRepository inbox;
  late final TicketRepository tickets;
  late final RigConnectivity connectivity;
  late final FakeShell shell;
  late final InboxController controller;
  final routes = <String, Route>{};

  /// What the controller asked of the server, by action.
  List<String> get asked => [for (final c in socket.calls) c.action];

  List<Map<String, dynamic>> argsOf(String action) => [
    for (final c in socket.calls)
      if (c.action == action) c.args,
  ];

  List<int> get ids => [for (final InboxRow r in controller.rows) r.id];

  void dispose() {
    tickets.onClose();
    controller.onClose();
  }
}
