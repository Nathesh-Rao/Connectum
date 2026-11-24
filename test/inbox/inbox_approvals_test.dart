import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/models/approval_pane.dart';
import 'package:connectum/features/inbox/models/approval_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

Map<String, dynamic> raw(
  int id, {
  String type = 'submission',
  String status = 'pending',
  bool canRespond = true,
  String direction = 'incoming',
  int? createdTs,
}) => {
  'id': id,
  'type': type,
  'status': status,
  'from': 'rhea',
  'fromName': 'Rhea',
  'approvers': ['ana'],
  'direction': direction,
  'canRespond': canRespond,
  'createdTs': createdTs ?? 1000 + id,
  'data': {'caption': 'Expense $id'},
};

Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
  'requests': rows,
  'total': rows.length,
  'hasMore': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  InboxController start(InboxRig r, {List<Map<String, dynamic>>? rows}) {
    rig = r;
    addTearDown(r.dispose);
    r.routes['records.query'] = (_) => queryReply([record(1)]);
    r.routes['req.list'] = (_) => page(
      rows ??
          [
            raw(1),
            raw(2, type: 'associate'),
            raw(3, canRespond: false, direction: 'outgoing'),
            raw(4, status: 'accepted', canRespond: false),
          ],
    );
    r.controller.onInit();
    return r.controller;
  }

  group('the button and the count', () {
    test(
      'the Inbox tab reads req.list once; the count is waiting for me',
      () async {
        final c = start(InboxRig());
        await settle();
        expect(rig.asked.where((a) => a == 'req.list'), hasLength(1));
        expect(c.approvals.count, 2);
      },
    );

    test('the button toggles the pane and back, saving nothing', () async {
      final c = start(InboxRig());
      await settle();
      expect(c.isApprovalsOpen.value, isFalse);
      c.toggleApprovals();
      expect(c.isApprovalsOpen.value, isTrue);
      c.toggleApprovals();
      expect(c.isApprovalsOpen.value, isFalse);
      expect(rig.asked.where((a) => a == 'req.list'), hasLength(1));
    });

    test('a request from the shell opens the pane, once', () async {
      final r = InboxRig();
      r.shell.approvalsRequest.value = true;
      final c = start(r);
      await settle();
      expect(c.isApprovalsOpen.value, isTrue);
      expect(r.shell.approvalsRequest.value, isFalse);
      c.toggleApprovals();
      r.shell.approvalsRequest.value = true;
      await settle();
      expect(c.isApprovalsOpen.value, isTrue);
    });

    test('Apply and Clear close the pane', () async {
      final c = start(InboxRig());
      await settle();
      c.openApprovals();
      c.applyFilter(c.filter.value.copyWith(wheres: const []));
      expect(c.isApprovalsOpen.value, isFalse);
      c.openApprovals();
      c.clearFilter();
      expect(c.isApprovalsOpen.value, isFalse);
    });

    test('a new session closes the pane and forgets the list', () async {
      final c = start(InboxRig());
      await settle();
      c.openApprovals();
      rig.store.switchTo('zed');
      await settle();
      expect(c.isApprovalsOpen.value, isFalse);
    });
  });

  group('the pane', () {
    test('rows: every state, newest first, with counts per answer', () async {
      final c = start(
        InboxRig(),
        rows: [
          raw(1, createdTs: 10),
          raw(2, status: 'rejected', canRespond: false, createdTs: 30),
          raw(3, status: 'accepted', canRespond: false, createdTs: 20),
          raw(
            4,
            type: 'onboarding',
            status: 'accepted',
            canRespond: false,
            createdTs: 40,
          ),
        ],
      );
      await settle();
      final a = c.approvals;
      expect([for (final r in a.rows) r.id], [2, 3, 1]);
      expect(a.counts[ApprovalFilter.all], 3);
      expect(a.offered, [
        ApprovalFilter.all,
        ApprovalFilter.pending,
        ApprovalFilter.approved,
        ApprovalFilter.rejected,
      ]);
      a.select(ApprovalFilter.rejected);
      expect([for (final r in a.rows) r.id], [2]);
    });

    test('the Inbox search narrows the approvals', () async {
      final c = start(InboxRig());
      await settle();
      c.onQueryChanged('Expense 2');
      await settle();
      expect(c.approvals.rows, isEmpty);
      c.onQueryChanged('Expense 1');
      expect([for (final r in c.approvals.rows) r.id], [1]);
      c.onQueryChanged('zzz');
      expect(c.approvals.viewState, AppViewState.noResults);
    });

    test('nothing read yet is loading; no approvals is empty', () async {
      final r = InboxRig();
      final c = start(r, rows: const []);
      expect(c.approvals.viewState, AppViewState.loading);
      await settle();
      expect(c.approvals.viewState, AppViewState.empty);
    });

    test('a failed read keeps the list; with none it is the error', () async {
      final c = start(InboxRig());
      await settle();
      rig.routes['req.list'] = (_) => throw const SocketCallError('server');
      await c.approvals.reload();
      expect(c.approvals.hasError, isTrue);
      expect(c.approvals.rows, isNotEmpty);
      expect(c.approvals.viewState, AppViewState.content);

      final r2 = InboxRig();
      r2.routes['req.list'] = (_) => throw const SocketCallError('server');
      r2.routes['records.query'] = (_) => queryReply([]);
      addTearDown(r2.dispose);
      r2.controller.onInit();
      await settle();
      expect(r2.controller.approvals.viewState, AppViewState.error);
    });

    test('offline with nothing read shows the offline state', () async {
      final r = InboxRig(isOnline: false);
      final c = start(r);
      await settle();
      expect(c.approvals.viewState, AppViewState.offline);
      r.connectivity.set(AppConnectivity.offline);
    });
  });

  group('answers', () {
    Future<InboxController> ready([List<Map<String, dynamic>>? rows]) async {
      final c = start(InboxRig(), rows: rows);
      await settle();
      rig.routes['req.respond'] = (args) => {
        'request': {
          ...raw(args['id'] as int),
          'status': args['action'] == 'accept' ? 'accepted' : 'rejected',
          'canRespond': false,
        },
      };
      return c;
    }

    Map<String, dynamic> sent() => rig.argsOf('req.respond').last;

    test(
      'approve is one tap: id and action only, then the list is read again',
      () async {
        final c = await ready();
        final reads = rig.asked.where((a) => a == 'req.list').length;
        final form = c.approvals.rows.firstWhere((r) => r.id == 1);
        expect(await c.approvals.respond(form, ApprovalAction.accept), isTrue);
        expect(sent(), {'id': 1, 'action': 'accept'});
        expect(c.approvals.leaving, contains(1));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await settle();
        expect(rig.asked.where((a) => a == 'req.list').length, reads + 1);
        expect(c.approvals.leaving, isEmpty);
      },
    );

    test('a form decline without a reason sends nothing', () async {
      final c = await ready();
      final form = c.approvals.rows.firstWhere((r) => r.id == 1);
      expect(
        await c.approvals.respond(form, ApprovalAction.reject, reason: ' '),
        isFalse,
      );
      expect(rig.argsOf('req.respond'), isEmpty);
    });

    test('a form decline sends reason, comment and allowResubmit', () async {
      final c = await ready();
      final form = c.approvals.rows.firstWhere((r) => r.id == 1);
      await c.approvals.respond(
        form,
        ApprovalAction.reject,
        reason: 'No receipt',
        comment: 'Attach it',
        allowResubmit: true,
      );
      expect(sent(), {
        'id': 1,
        'action': 'reject',
        'reason': 'No receipt',
        'comment': 'Attach it',
        'allowResubmit': true,
      });
    });

    test('a return is a form only and always has a reason', () async {
      final c = await ready();
      final form = c.approvals.rows.firstWhere((r) => r.id == 1);
      expect(await c.approvals.respond(form, ApprovalAction.returnIt), isFalse);
      await c.approvals.respond(
        form,
        ApprovalAction.returnIt,
        reason: 'Missing',
        allowResubmit: true,
      );
      expect(sent(), {'id': 1, 'action': 'return', 'reason': 'Missing'});
      expect(
        ApprovalRules.actionsFor(c.approvals.rows.firstWhere((r) => r.id == 2)),
        isNot(contains(ApprovalAction.returnIt)),
      );
    });

    test('a connection decline goes with no reason', () async {
      final c = await ready();
      final conn = c.approvals.rows.firstWhere((r) => r.id == 2);
      expect(await c.approvals.respond(conn, ApprovalAction.reject), isTrue);
      expect(sent(), {'id': 2, 'action': 'reject'});
    });

    test('dismiss sends ignore', () async {
      final c = await ready();
      final form = c.approvals.rows.firstWhere((r) => r.id == 1);
      await c.approvals.respond(form, ApprovalAction.ignore);
      expect(sent(), {'id': 1, 'action': 'ignore'});
    });

    test('a refused answer is not replayed; the list is read again', () async {
      final c = await ready();
      rig.routes['req.respond'] = (_) => throw const SocketCallError(
        'already_resolved',
        'That request has already been answered.',
      );
      final reads = rig.asked.where((a) => a == 'req.list').length;
      final form = c.approvals.rows.firstWhere((r) => r.id == 1);
      expect(await c.approvals.respond(form, ApprovalAction.accept), isFalse);
      await settle();
      expect(rig.argsOf('req.respond'), hasLength(1));
      expect(rig.asked.where((a) => a == 'req.list').length, reads + 1);
      expect(c.approvals.leaving, isEmpty);
      expect(c.approvals.busy, isEmpty);
    });

    test(
      'only the server decides: a request I cannot answer has no buttons',
      () async {
        final c = await ready();
        final waiting = c.approvals.rows.firstWhere((r) => r.id == 3);
        expect(ApprovalRules.actionsFor(waiting), isEmpty);
      },
    );
  });
}
