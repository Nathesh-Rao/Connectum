import 'dart:async';

import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  InboxController start(InboxRig r) {
    rig = r;
    addTearDown(r.dispose);
    r.controller.onInit();
    return r.controller;
  }

  group('states', () {
    test('loading until the first answer, then the records', () async {
      final r = InboxRig();
      final held = Completer<Map<String, dynamic>>();
      r.routes['records.query'] = (_) => held.future;
      final c = start(r);
      await settle();
      expect(c.viewState.value, AppViewState.loading);
      held.complete(queryReply([record(3), record(2), record(1)], total: 3));
      await settle();
      expect(c.viewState.value, AppViewState.content);
      expect(rig.ids, [3, 2, 1]);
      expect(c.totalLabel, '3 records');
    });

    test('opens with records.query, records.counts, people.cards only', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([record(1)]);
      start(r);
      await settle();
      expect(r.asked.toSet(), {
        'records.query',
        'records.counts',
        'people.cards',
      });
      expect(r.argsOf('records.query').single, {
        'scope': ['me'],
        'limit': 50,
        'offset': 0,
      });
      expect(r.argsOf('people.cards').single['usernames'], ['ana']);
    });

    test('empty', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([]);
      final c = start(r);
      await settle();
      expect(c.viewState.value, AppViewState.empty);
      expect(c.totalLabel, '0 records');
    });

    test('an error with no list shows the error, retry reads again', () async {
      final r = InboxRig();
      var isFailing = true;
      r.routes['records.query'] = (_) => isFailing
          ? throw const SocketCallError('server_error')
          : queryReply([record(1)]);
      final c = start(r);
      await settle();
      expect(c.viewState.value, AppViewState.error);
      isFailing = false;
      await c.retry();
      await settle();
      expect(c.viewState.value, AppViewState.content);
      expect(rig.ids, [1]);
      expect(c.hasError.value, isFalse);
    });

    test('an error keeps the old list on screen', () async {
      final r = InboxRig();
      var isFailing = false;
      r.routes['records.query'] = (_) => isFailing
          ? throw const SocketCallError('server_error')
          : queryReply([record(2), record(1)]);
      final c = start(r);
      await settle();
      isFailing = true;
      await c.refreshList();
      await settle();
      expect(c.hasError.value, isTrue);
      expect(c.viewState.value, AppViewState.content);
      expect(rig.ids, [2, 1]);
      expect(InboxController.errorText,
          'The records could not be read. Use Refresh to try again.');
    });

    test('offline with nothing read shows the offline state', () async {
      final r = InboxRig(isOnline: false);
      final c = start(r);
      await settle();
      expect(c.viewState.value, AppViewState.offline);
      expect(r.asked, isEmpty);
    });

    test('offline with a list keeps it, no error', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([record(1)]);
      final c = start(r);
      await settle();
      r.socket.goOffline();
      r.connectivity.set(AppConnectivity.offline);
      await c.refreshList();
      await settle();
      expect(c.viewState.value, AppViewState.content);
      expect(c.hasError.value, isFalse);
      expect(rig.ids, [1]);
    });

    test('a dropped connection during a read is not a list error', () async {
      final r = InboxRig();
      var isDropped = false;
      r.routes['records.query'] = (_) => isDropped
          ? throw const SocketCallError('timeout')
          : queryReply([record(1)]);
      final c = start(r);
      await settle();
      isDropped = true;
      await c.refreshList();
      await settle();
      expect(c.hasError.value, isFalse);
      expect(rig.ids, [1]);
    });

    test('back online reads again after an offline start', () async {
      final r = InboxRig(isOnline: false);
      r.routes['records.query'] = (_) => queryReply([record(7)]);
      final c = start(r);
      await settle();
      r.socket.goOnline();
      r.connectivity.set(AppConnectivity.online);
      await settle();
      expect(c.viewState.value, AppViewState.content);
      expect(rig.ids, [7]);
    });

    test('a capped list says 1000+', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) =>
          queryReply([record(1)], total: 1001, hasMore: true, capped: true);
      final c = start(r);
      await settle();
      expect(c.totalLabel, '1000+ records');
    });
  });

  group('scope', () {
    test('My Team is hidden when there are no reports', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([record(1)]);
      final c = start(r);
      await settle();
      expect(c.isTeamShown, isFalse);
      c.selectScope(InboxScope.team);
      await settle();
      expect(c.scope.value, InboxScope.me);
      expect(r.argsOf('records.query').length, 1);
    });

    test('My Team is hidden when records.counts fails', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([record(1)]);
      r.routes['records.counts'] = (_) =>
          throw const SocketCallError('server_error');
      final c = start(r);
      await settle();
      expect(c.isTeamShown, isFalse);
      expect(rig.ids, [1]);
    });

    test('with reports the switch asks scope team and replaces the list', () async {
      final r = InboxRig();
      r.routes['records.counts'] = (_) => countsReply(reports: 2);
      r.routes['records.query'] = (a) => (a['scope'] as List).first == 'team'
          ? queryReply([record(9, holder: 'ben')])
          : queryReply([record(1)]);
      final c = start(r);
      await settle();
      expect(c.isTeamShown, isTrue);
      c.selectScope(InboxScope.team);
      expect(c.page.value, isNull);
      await settle();
      expect(r.argsOf('records.query').last['scope'], ['team']);
      expect(rig.ids, [9]);
      c.selectScope(InboxScope.me);
      await settle();
      expect(r.argsOf('records.query').last['scope'], ['me']);
      expect(rig.ids, [1]);
    });

    test('an answer for a scope that was left is dropped', () async {
      final r = InboxRig();
      r.routes['records.counts'] = (_) => countsReply(reports: 2);
      final held = <String, Completer<Map<String, dynamic>>>{};
      var asks = 0;
      r.routes['records.query'] = (a) {
        if (asks++ == 0) return queryReply([record(1)]);
        return (held['$asks${(a['scope'] as List).first}'] =
                Completer<Map<String, dynamic>>())
            .future;
      };
      final c = start(r);
      await settle();
      c.selectScope(InboxScope.team); // ask 2, waits
      await settle();
      c.selectScope(InboxScope.me); // ask 3, queued behind it
      await settle();
      held['2team']!.complete(queryReply([record(9, holder: 'ben')]));
      await settle();
      expect(rig.ids, isNot(contains(9)));
      held['3me']!.complete(queryReply([record(5)]));
      await settle();
      expect(c.scope.value, InboxScope.me);
      expect(rig.ids, [5]);
    });
  });

  group('paging', () {
    test('the next page is added after the first, each record once', () async {
      final r = InboxRig();
      r.routes['records.query'] = (a) => a['offset'] == 0
          ? queryReply(
              [record(5), record(4), record(3)],
              total: 5,
              hasMore: true,
            )
          : queryReply([record(3), record(2), record(1)], total: 5);
      final c = start(r);
      await settle();
      expect(c.hasMore, isTrue);
      await c.loadMore();
      await settle();
      expect(r.argsOf('records.query').last, {
        'scope': ['me'],
        'limit': 50,
        'offset': 3,
      });
      expect(rig.ids, [5, 4, 3, 2, 1]);
      expect(c.hasMore, isFalse);
      expect(c.isLoadingMore.value, isFalse);
    });

    test('nothing is asked when there is no more', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([record(1)]);
      final c = start(r);
      await settle();
      await c.loadMore();
      expect(r.argsOf('records.query').length, 1);
    });

    test('two load-mores at once ask once', () async {
      final r = InboxRig();
      r.routes['records.query'] = (a) => a['offset'] == 0
          ? queryReply([record(2)], total: 2, hasMore: true)
          : queryReply([record(1)], total: 2);
      final c = start(r);
      await settle();
      unawaited(c.loadMore());
      unawaited(c.loadMore());
      await settle();
      expect(r.argsOf('records.query').length, 2);
    });

    test('a refresh asks for as many records as are shown', () async {
      final r = InboxRig();
      r.routes['records.query'] = (a) {
        final from = 120 - (a['offset'] as int);
        final n = (a['limit'] as int).clamp(0, 120 - (a['offset'] as int));
        return queryReply(
          [for (var i = from; i > from - n; i--) record(i)],
          total: 120,
          hasMore: true,
        );
      };
      final c = start(r);
      await settle();
      await c.loadMore();
      await settle();
      await c.refreshList();
      await settle();
      expect(r.argsOf('records.query').last['limit'], 100);
    });
  });

  group('search', () {
    test('filters the loaded records; no match is its own state', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([
        record(2, values: {'title': 'Printer jammed'}),
        record(1, values: {'title': 'Invoice mismatch'}),
      ]);
      final c = start(r);
      await settle();
      c.onQueryChanged('printer');
      expect(rig.ids, [2]);
      c.onQueryChanged('nothing like it');
      expect(rig.ids, isEmpty);
      expect(c.viewState.value, AppViewState.noResults);
      c.clearSearch();
      expect(rig.ids, [2, 1]);
      expect(c.viewState.value, AppViewState.content);
      expect(r.argsOf('records.query').length, 1);
    });
  });

  group('session', () {
    test('another person clears the list and reads again', () async {
      final r = InboxRig();
      r.routes['records.query'] = (_) => queryReply([record(1)]);
      final c = start(r);
      await settle();
      r.store.switchTo('ben');
      await settle();
      expect(r.argsOf('records.query').length, 2);
      expect(c.me, 'ben');
    });
  });
}
