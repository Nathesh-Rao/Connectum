import 'dart:async';

import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/inbox_views_controller.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_saved_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

/// A tiny server for the four view commands: one document, last write wins.
class ViewServer {
  ViewServer(
    InboxRig rig, {
    List<Map<String, dynamic>> initial = const [],
    this.defaultName,
  }) : views = [...initial] {
    rig.routes['inbox.views.get'] = (_) => doc();
    rig.routes['inbox.views.save'] = (a) {
      if (saveError != null) throw saveError!;
      final name = a['name'] as String;
      final v = {'name': name, 'view': a['view'], 'savedTs': 1};
      views.removeWhere((x) => x['name'] == name);
      views.add(v);
      if (a['default'] == true) defaultName = name;
      return doc();
    };
    rig.routes['inbox.views.delete'] = (a) {
      views.removeWhere((x) => x['name'] == a['name']);
      if (defaultName == a['name']) defaultName = null;
      return doc();
    };
    rig.routes['inbox.views.default'] = (a) {
      defaultName = a['name'] as String?;
      return doc();
    };
  }

  final List<Map<String, dynamic>> views;
  String? defaultName;
  Object? saveError;

  Map<String, dynamic> doc() => {
    'views': [...views],
    'default': defaultName,
  };

  Map<String, dynamic>? named(String n) =>
      views.where((v) => v['name'] == n).firstOrNull;
}

Map<String, dynamic> sv(String name, Map<String, dynamic> view) => {
  'name': name,
  'view': view,
  'savedTs': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  late ViewServer server;

  InboxController start(
    List<Map<String, dynamic>> views, {
    String? def,
    bool isOnline = true,
  }) {
    rig = InboxRig(isOnline: isOnline);
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) => queryReply([record(1)]);
    server = ViewServer(rig, initial: views, defaultName: def);
    rig.controller.onInit();
    return rig.controller;
  }

  final requestsView = {
    'folder': 'requests',
    'sort': 'oldest',
    'filters': {
      'forms': ['t'],
      'status': 'open',
    },
  };

  group('opening', () {
    test(
      'the Default View opens at start, even when another is the default',
      () async {
        final c = start([
          sv('Mine', {'folder': 'completed'}),
          sv('Default View', requestsView),
        ], def: 'Mine');
        await settle();
        expect(c.filter.value.wheres, ['requests']);
        expect(c.filter.value.sort, 'oldest');
        expect(c.views.current.value, '');
        expect(c.isViewChanged, isFalse);
        expect(rig.argsOf('records.query').last['views'], isNotEmpty);
      },
    );

    test('without a Default View the one named by default opens', () async {
      final c = start([
        sv('Mine', {'folder': 'completed'}),
      ], def: 'Mine');
      await settle();
      expect(c.filter.value.wheres, ['completed']);
      expect(c.views.current.value, 'Mine');
      expect(c.isViewChanged, isFalse);
    });

    test('nothing saved: the plain list, no change', () async {
      final c = start([]);
      await settle();
      expect(c.filter.value.isActive(), isFalse);
      expect(c.isViewChanged, isFalse);
    });

    test('a person who already started is not moved to the view', () async {
      final held = Completer<Map<String, dynamic>>();
      final c = start([sv('Default View', requestsView)]);
      rig.routes['inbox.views.get'] = (_) => held.future;
      await settle();
      c.applyFilter(const InboxFilter(sort: 'desc'));
      held.complete(server.doc());
      await settle();
      expect(c.filter.value.sort, 'desc');
      expect(c.filter.value.wheres, isEmpty);
    });

    test(
      'a failed get keeps the screen as it is and the error shows',
      () async {
        final c = start([]);
        rig.routes['inbox.views.get'] = (_) =>
            throw const SocketCallError('timeout');
        await c.views.load();
        expect(c.views.hasLoadError, isTrue);
      },
    );

    test(
      'opening a view closes the approvals pane and reads page one',
      () async {
        final c = start([sv('A', requestsView)]);
        await settle();
        c.openApprovals();
        final before = rig.argsOf('records.query').length;
        expect(await c.openView('A'), isTrue);
        await settle();
        expect(c.isApprovalsOpen.value, isFalse);
        expect(c.views.current.value, 'A');
        expect(rig.argsOf('records.query').length, greaterThan(before));
        expect(rig.argsOf('records.query').last['offset'], 0);
        expect(c.filter.value.wheres, ['requests']);
      },
    );

    test('a view that was never saved is the plain list', () async {
      final c = start([sv('A', requestsView)]);
      await settle();
      await c.openView('A');
      await c.openView('');
      await settle();
      expect(c.views.current.value, '');
      expect(c.filter.value.isActive(), isFalse);
    });

    test(
      'a view with a team scope opens on Me when the person has no team',
      () async {
        final c = start([
          sv('T', {
            'scopePick': ['team'],
          }),
        ]);
        await settle();
        await c.openView('T');
        await settle();
        expect(c.scope.value, InboxScope.me);
      },
    );
  });

  group('changed', () {
    test('a changed filter marks the view, saving clears it', () async {
      final c = start([sv('Default View', requestsView)]);
      await settle();
      expect(c.isViewChanged, isFalse);
      c.applyFilter(c.filter.value.copyWith(sort: 'desc'));
      expect(c.isViewChanged, isTrue);
      expect(await c.saveView(), '');
      expect(c.isViewChanged, isFalse);
      expect(server.named('Default View')!['view']['sort'], 'desc');
    });

    test('saving the Default View makes it the default', () async {
      final c = start([]);
      await settle();
      c.applyFilter(const InboxFilter(sort: 'asc'));
      await c.saveView();
      expect(server.defaultName, 'Default View');
      expect(
        rig.asked.where((a) => a == 'inbox.views.get').length,
        greaterThan(1),
      );
    });

    test(
      'a web view opens, is saved after a change, and keeps its other keys',
      () async {
        final web = {
          'folder': 'task',
          'lens': 'team',
          'kinds': ['broadcast'],
          'approvalPick': ['pending'],
          'teamMembers': ['ravi'],
          'sort': 'oldest',
          'timing': {
            'period': 'week',
            'from': '',
            'to': '',
            'hours': [0, 1440],
          },
        };
        final c = start([sv('Web', web)]);
        await settle();
        await c.openView('Web');
        expect(c.isViewChanged, isFalse);
        c.applyFilter(c.filter.value.copyWith(forms: const ['t']));
        expect(c.isViewChanged, isTrue);
        expect(await c.saveView(), '');
        final saved = server.named('Web')!['view'] as Map;
        expect(saved['folder'], 'task');
        expect(saved['lens'], 'team');
        expect(saved['kinds'], ['broadcast']);
        expect(saved['approvalPick'], ['pending']);
        expect(saved['teamMembers'], ['ravi']);
        expect((saved['timing'] as Map)['period'], 'week');
        expect((saved['filters'] as Map)['forms'], ['t']);
        expect(c.isViewChanged, isFalse);
      },
    );
  });

  group('Save your changes?', () {
    Future<InboxController> changed() async {
      final c = start([
        sv('A', requestsView),
        sv('B', {'folder': 'completed'}),
      ]);
      await settle();
      await c.openView('A');
      await settle();
      c.applyFilter(c.filter.value.copyWith(forms: const ['u']));
      return c;
    }

    Future<bool> askAndAnswer(
      InboxController c,
      Future<bool> Function() trigger,
      UnsavedChoice choice,
    ) async {
      final done = trigger();
      await settle();
      final prompt = c.unsavedPrompt.value;
      expect(prompt, isNotNull, reason: 'the question is asked');
      prompt!.reply(choice);
      return done;
    }

    test('switching to another view asks; Cancel keeps the draft', () async {
      final c = await changed();
      final went = await askAndAnswer(
        c,
        () => c.openView('B'),
        UnsavedChoice.cancel,
      );
      expect(went, isFalse);
      expect(c.views.current.value, 'A');
      expect(c.filter.value.forms, ['u']);
      expect(c.unsavedPrompt.value, isNull);
    });

    test(
      'switching, Discard: the other view opens and nothing is saved',
      () async {
        final c = await changed();
        final went = await askAndAnswer(
          c,
          () => c.openView('B'),
          UnsavedChoice.discard,
        );
        await settle();
        expect(went, isTrue);
        expect(c.views.current.value, 'B');
        expect(
          (server.named('A')!['view'] as Map)['filters'],
          requestsView['filters'],
        );
        expect(c.isViewChanged, isFalse);
      },
    );

    test(
      'switching, Save: the open view is saved, then the other opens',
      () async {
        final c = await changed();
        final went = await askAndAnswer(
          c,
          () => c.openView('B'),
          UnsavedChoice.save,
        );
        await settle();
        expect(went, isTrue);
        expect(
          ((server.named('A')!['view'] as Map)['filters'] as Map)['forms'],
          ['u'],
        );
        expect(c.views.current.value, 'B');
      },
    );

    test('Save that fails stays where it is', () async {
      final c = await changed();
      server.saveError = const SocketCallError(
        'invalid',
        'The view is too big.',
      );
      final went = await askAndAnswer(
        c,
        () => c.openView('B'),
        UnsavedChoice.save,
      );
      expect(went, isFalse);
      expect(c.views.current.value, 'A');
      expect(c.filter.value.forms, ['u']);
    });

    test(
      'creating a view asks first; Discard puts the saved setup back',
      () async {
        final c = await changed();
        final go = await askAndAnswer(c, c.confirmLeave, UnsavedChoice.discard);
        await settle();
        expect(go, isTrue);
        expect(c.filter.value.forms, ['t']);
        expect(c.filter.value.wheres, ['requests']);
        expect(c.isViewChanged, isFalse);
        expect(await c.createView('Fresh'), '');
        await settle();
        expect(c.views.current.value, 'Fresh');
        expect(c.filter.value.isActive(), isFalse);
        expect(server.named('Fresh'), isNotNull);
      },
    );

    test(
      'the back button is blocked while the change is not saved, and asks',
      () async {
        final c = await changed();
        expect(c.isBackBlocked, isTrue);
        final go = await askAndAnswer(c, c.confirmLeave, UnsavedChoice.cancel);
        expect(go, isFalse);
        expect(c.isBackBlocked, isTrue);
        final go2 = await askAndAnswer(
          c,
          c.confirmLeave,
          UnsavedChoice.discard,
        );
        expect(go2, isTrue);
        expect(c.isBackBlocked, isFalse);
      },
    );

    test('switching tabs never asks, each tab keeps its state', () async {
      final c = await changed();
      rig.shell.tab.value = HomeTab.chats;
      await settle();
      expect(c.unsavedPrompt.value, isNull);
      expect(c.isBackBlocked, isFalse);
      expect(c.filter.value.forms, ['u']);
      rig.shell.tab.value = HomeTab.inbox;
      await settle();
      expect(c.unsavedPrompt.value, isNull);
      expect(c.filter.value.forms, ['u']);
      expect(c.isBackBlocked, isTrue);
    });

    test('nothing changed: no question', () async {
      final c = start([sv('A', requestsView)]);
      await settle();
      expect(await c.openView('A'), isTrue);
      expect(c.unsavedPrompt.value, isNull);
      expect(c.isBackBlocked, isFalse);
    });
  });

  group('actions', () {
    test(
      'Save as new: name rules answer without a call, then a read and a save',
      () async {
        final c = start([sv('A', requestsView)]);
        await settle();
        final before = rig.asked.length;
        expect(await c.saveAsNew('   '), InboxViewRules.empty);
        expect(await c.saveAsNew('default view'), InboxViewRules.reserved);
        expect(await c.saveAsNew('a'), InboxViewRules.taken);
        expect(rig.asked.length, before, reason: 'refused before any call');
        expect(await c.saveAsNew('  My  new view '), '');
        expect(server.named('My new view'), isNotNull);
        expect(c.views.current.value, 'My new view');
        expect(c.isViewChanged, isFalse);
      },
    );

    test('20 views: a new name is refused, with the fresh list', () async {
      final c = start([
        for (var i = 0; i < 20; i++) sv('V$i', {'folder': 'data'}),
      ]);
      await settle();
      expect(await c.saveAsNew('One more'), InboxViewRules.tooMany);
    });

    test("the server's message shows and the sheet keeps it", () async {
      final c = start([]);
      await settle();
      server.saveError = const SocketCallError(
        'invalid',
        'The view is too big.',
      );
      expect(await c.saveView(), 'The view is too big.');
      expect(c.views.problem.value, 'The view is too big.');
      expect(await c.saveAsNew('Big'), 'The view is too big.');
    });

    test('Set as default and Clear default for a named view', () async {
      final c = start([sv('A', requestsView)]);
      await settle();
      await c.openView('A');
      expect(c.views.isOpenDefault, isFalse);
      expect(await c.toggleDefault(), '');
      expect(server.defaultName, 'A');
      expect(c.views.isOpenDefault, isTrue);
      expect(await c.toggleDefault(), '');
      expect(server.defaultName, isNull);
      expect(rig.asked, contains('inbox.views.default'));
    });

    test('Remove: the view goes and the Default View opens', () async {
      final c = start([
        sv('A', requestsView),
        sv('Default View', {'folder': 'completed'}),
      ]);
      await settle();
      await c.openView('A');
      expect(await c.removeView(), '');
      await settle();
      expect(server.named('A'), isNull);
      expect(c.views.current.value, '');
      expect(c.filter.value.wheres, ['completed']);
    });

    test('offline: the list stays, writes are refused with a note', () async {
      final c = start([sv('A', requestsView)], isOnline: false);
      await settle();
      expect(c.views.isOffline, isTrue);
      expect(await c.saveView(), InboxViews.stillLoading);
      await c.refreshViews();
      expect(rig.asked.where((a) => a.startsWith('inbox.views')), isEmpty);
    });
  });
}
