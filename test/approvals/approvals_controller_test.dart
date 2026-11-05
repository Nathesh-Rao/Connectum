import 'dart:async';

import 'package:connectum/data/repositories/approval_repository.dart';
import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/approvals/approvals_controller.dart';
import 'package:connectum/features/approvals/models/approval_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';
import '../support/postman.dart';

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late ApprovalRepository repo;
  late FeedRepository feed;
  late ApprovalsController c;

  final waiting = Postman.instance.data('req.list: an approval waiting for me');

  Map<String, dynamic> answered(String status, {String reason = ''}) {
    final r = (waiting['requests'] as List).first as Map;
    return {
      'request': {
        ...r,
        'status': status,
        'canRespond': false,
        'resolvedBy': 'meg',
        'resolvedByName': 'Meg Manager',
        'resolvedTs': 5,
        if (reason.isNotEmpty) 'reason': reason,
      },
    };
  }

  setUp(() async {
    socket = FakeSocket()..goOnline();
    final store = FakeStore(user: 'meg');
    feed = FeedRepository(socket, store, FakeE2e())..onInit();
    repo = ApprovalRepository(socket, store, feed)..onInit();
    socket.answers['req.list'] = waiting;
    socket.answers['feed.summary'] = <String, dynamic>{};
    socket.answers['feed.list'] = <String, dynamic>{};
    c = ApprovalsController(approvals: repo, connectivity: FakeConnectivity())
      ..onInit();
    await _settle();
  });

  tearDown(() {
    c.onClose();
    repo.onClose();
    feed.onClose();
  });

  Map<String, dynamic> lastArgs() =>
      socket.calls.lastWhere((x) => x.action == 'req.respond').args;

  test('the real "waiting for me" reply: one card, answerable', () {
    expect(socket.calls.first.action, 'req.list');
    expect(socket.calls.first.args, {'status': 'pending', 'limit': 50});
    expect(c.items, hasLength(1));
    expect(ApprovalRules.actionsFor(c.items.first), hasLength(4));
  });

  test(
    'accept sends id and action only; the card shows its new state',
    () async {
      socket.answers['req.respond'] = answered('accepted');
      final r = c.items.first;
      expect(await c.respond(r, ApprovalAction.accept), isTrue);
      expect(lastArgs(), {'id': 1, 'action': 'accept'});
      expect(c.find(1)!.status, 'accepted');
      expect(ApprovalRules.actionsFor(c.find(1)!), isEmpty);
    },
  );

  test(
    'reject without a reason sends nothing; with one it carries reason, comment, allowResubmit',
    () async {
      final r = c.items.first;
      expect(await c.respond(r, ApprovalAction.reject, reason: ' '), isFalse);
      expect(socket.count('req.respond'), 0);
      socket.answers['req.respond'] = answered(
        'rejected',
        reason: 'No receipt',
      );
      expect(
        await c.respond(
          r,
          ApprovalAction.reject,
          reason: 'No receipt',
          comment: 'Please attach it',
          allowResubmit: true,
        ),
        isTrue,
      );
      expect(lastArgs(), {
        'id': 1,
        'action': 'reject',
        'reason': 'No receipt',
        'comment': 'Please attach it',
        'allowResubmit': true,
      });
    },
  );

  test('already_resolved: not replayed, the list is read again', () async {
    socket.answers['req.respond'] = const SocketCallError(
      'already_resolved',
      'That request has already been answered.',
    );
    final reads = socket.count('req.list');
    expect(await c.respond(c.items.first, ApprovalAction.accept), isFalse);
    await _settle();
    expect(socket.count('req.respond'), 1);
    expect(socket.count('req.list'), greaterThan(reads));
    expect(c.isBusy.value, isFalse);
  });

  test('a lost answer is not replayed by the app', () async {
    socket.answers['req.respond'] = const SocketCallError('timeout');
    expect(await c.respond(c.items.first, ApprovalAction.ignore), isFalse);
    await _settle();
    expect(socket.count('req.respond'), 1);
  });

  test(
    'not_found removes the card; forbidden keeps it and reads again',
    () async {
      socket.answers['req.respond'] = const SocketCallError(
        'forbidden',
        "This request isn't yours to answer.",
      );
      await c.respond(c.items.first, ApprovalAction.accept);
      await _settle();
      expect(c.find(1), isNotNull);
      socket.answers['req.respond'] = const SocketCallError(
        'not_found',
        'No such request.',
      );
      await c.respond(c.items.first, ApprovalAction.accept);
      expect(c.find(1), isNull);
    },
  );

  test('a double tap sends one answer', () async {
    final gate = Completer<void>();
    socket.held['req.respond'] = gate.future;
    socket.answers['req.respond'] = answered('accepted');
    final r = c.items.first;
    final a = c.respond(r, ApprovalAction.accept);
    final b = c.respond(r, ApprovalAction.accept);
    gate.complete();
    expect(await b, isFalse);
    expect(await a, isTrue);
    expect(socket.count('req.respond'), 1);
  });

  test(
    'request_created / request_resolved events: card in place, feed read too',
    () async {
      final created = Map<String, dynamic>.from(
        (waiting['requests'] as List).first as Map,
      )..['id'] = 2;
      repo.onEvent({
        'type': 'sd_event',
        'event': 'request_created',
        'data': created,
      });
      await _settle();
      expect(c.items.map((r) => r.id), containsAll([1, 2]));
      final reads = socket.count('req.list');
      repo.onEvent({
        'type': 'sd_event',
        'event': 'request_resolved',
        'data': {
          'request': {...created, 'status': 'accepted', 'resolvedBy': 'zed'},
        },
      });
      await _settle();
      expect(c.find(2)!.status, 'accepted');
      expect(c.find(2)!.canRespond, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(socket.count('req.list'), greaterThan(reads));
      expect(socket.count('feed.list'), greaterThan(0));
    },
  );
}
