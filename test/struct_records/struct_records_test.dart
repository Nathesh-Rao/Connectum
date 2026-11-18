import 'dart:async';

import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/data/models/form_definition.dart';
import 'package:connectum/data/models/struct_records.dart';
import 'package:connectum/data/repositories/struct_records_repository.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/features/forms/models/form_launch.dart';
import 'package:connectum/features/struct_records/models/struct_records_launch.dart';
import 'package:connectum/features/struct_records/struct_records_controller.dart';
import 'package:connectum/features/struct_records/struct_records_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Fakes only: no socket, no server, no SQLite. [_Local] stands for the
/// device's database: the screen must never reach it on a tap.
class _Local {
  int calls = 0;
}

Map<String, dynamic> _sub(
  int id,
  String by, {
  String? status,
  Map<String, dynamic>? values,
  int ts = 0,
}) => {
  'id': id,
  'tstruct': 'leave',
  'by': by,
  'byName': by == 'alex' ? 'Alex Morgan' : 'Maya Iyer',
  'ts': ts == 0 ? 1000000 - id : ts,
  'status': ?status,
  'values': values ?? {'kind': 'Casual $id', 'days': id, 'secret': 'S-$id'},
};

Map<String, dynamic> _definition({
  String owner = 'boss',
  String? system,
  bool isHistory = false,
}) => {
  'caption': 'Leave request',
  'owner': owner,
  'keyField': 'kind',
  'system': ?system,
  if (isHistory) 'recordHistory': true,
  'fields': [
    {'name': 'kind', 'caption': 'Leave type', 'type': 'text'},
    {'name': 'days', 'caption': 'Days', 'type': 'wholenumber'},
    {
      'name': 'secret',
      'caption': 'Salary note',
      'type': 'text',
      'hidden': true,
    },
    {'name': 'proof', 'caption': 'Proof', 'type': 'file'},
  ],
};

class Rig {
  Rig({List<Map<String, dynamic>>? rows, Map<String, dynamic>? def})
    : rows = rows ?? [for (var i = 1; i <= 3; i++) _sub(i, 'alex')],
      def = def ?? _definition();

  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> def;
  final bool isAdmin = false;
  final String me = 'alex';
  final local = _Local();
  final asked = <Map<String, dynamic>>[];
  final deleted = <String>[];
  final commands = <String>[];
  bool isOnline = true;
  Object? failure;
  String? deleteAnswer;
  int definitionCalls = 0;

  late final repository = StructRecordsRepository(
    call: (command, args) async {
      commands.add(command);
      asked.add(args);
      final f = failure;
      if (f is SocketCallError) throw f;
      final only = args['recordsOnly'] == true;
      final list = [
        for (final r in rows)
          if (!only || (r['status'] != 'pending' && r['status'] != 'rejected'))
            r,
      ];
      final offset = (args['offset'] as int?) ?? 0;
      final limit = args['limit'] as int;
      final page = list.skip(offset).take(limit).toList();
      return {
        'submissions': page,
        'total': list.length,
        'hasMore': offset + page.length < list.length,
      };
    },
    isOnline: () => isOnline,
    me: () => me,
    isAdmin: () => isAdmin,
    definition: (name, scope) async {
      definitionCalls++;
      return FormDefinition.fromMap(name, scope, def);
    },
    deleteRecord: (id) async {
      deleted.add(id);
      if (deleteAnswer == null) {
        local.calls++;
        rows.removeWhere((r) => '${r['id']}' == id);
      }
      return deleteAnswer;
    },
  );

  final routes = <(String, Object?)>[];
  Object? routeResult;

  StructRecordsController controller({
    StructRecordsLaunch? launch,
    Duration delay = Duration.zero,
  }) => StructRecordsController(
    repository: repository,
    launch:
        launch ??
        const StructRecordsLaunch(
          name: 'leave',
          scope: 'user',
          caption: 'Leave request',
        ),
    editRefreshDelay: delay,
    openRoute: (route, args) async {
      routes.add((route, args));
      return routeResult;
    },
  );

  int get listCalls => asked.length;
}

/// Bounded pumps: never pumpAndSettle.
Future<void> pumpFor(WidgetTester tester, [int ms = 400]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<StructRecordsController> boot(
  WidgetTester tester,
  Rig rig, {
  StructRecordsController? controller,
}) async {
  Get.reset();
  final c = Get.put(controller ?? rig.controller());
  await tester.pumpWidget(
    const GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: StructRecordsView()),
    ),
  );
  await pumpFor(tester);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(Get.reset);

  group('records', () {
    testWidgets('load through the repository: records first, then my own '
        'waiting ones, newest first', (tester) async {
      final rig = Rig(
        rows: [
          _sub(1, 'alex'),
          _sub(2, 'maya'),
          _sub(3, 'alex', status: 'pending', ts: 2000000),
          _sub(4, 'maya', status: 'pending', ts: 3000000),
        ],
      );
      final c = await boot(tester, rig);
      expect(c.viewState.value, AppViewState.content);
      expect(rig.commands.toSet(), {'submissions.list'});
      expect(rig.asked.first, {
        'tstruct': 'leave',
        'recordsOnly': true,
        'limit': 50,
      });
      expect(rig.asked[1].containsKey('recordsOnly'), isFalse);
      expect(c.total.value, 2);
      expect(c.rows.map((r) => r.id), [3, 1, 2]);
      expect(find.text('2 records'), findsOneWidget);
      expect(find.text('Waiting for approval'), findsOneWidget);
    });

    testWidgets('the card shows the key field as title, No., and fields', (
      tester,
    ) async {
      final rig = Rig(
        rows: [
          _sub(
            7,
            'alex',
            values: {
              'kind': 'Sick leave',
              'days': 3,
              'proof': ['a' * 24, 'b' * 24],
            },
          ),
        ],
      );
      await boot(tester, rig);
      expect(find.text('Sick leave'), findsOneWidget);
      expect(find.text('No. 7'), findsOneWidget);
      expect(find.text('Days'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2 files'), findsOneWidget);
    });
  });

  group('who may Edit and Delete (the web: my own, not waiting)', () {
    testWidgets('buttons only on my records that are not pending', (
      tester,
    ) async {
      final rig = Rig(
        rows: [
          _sub(1, 'alex'),
          _sub(2, 'maya'),
          _sub(3, 'alex', status: 'pending'),
          _sub(4, 'alex', status: 'rejected'),
        ],
      );
      final c = await boot(tester, rig);
      bool can(int id) => c.canChange(c.rows.firstWhere((r) => r.id == id));
      expect(can(1), isTrue);
      expect(can(2), isFalse, reason: "someone else's record");
      expect(can(3), isFalse, reason: 'waiting for approval');
      expect(can(4), isTrue, reason: 'declined is not pending');
      expect(find.bySemanticsLabel('Edit record 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete record 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Edit record 4'), findsOneWidget);
      expect(find.bySemanticsLabel('Edit record 2'), findsNothing);
      expect(find.bySemanticsLabel('Delete record 2'), findsNothing);
      expect(find.bySemanticsLabel('Edit record 3'), findsNothing);
      expect(find.bySemanticsLabel('Delete record 3'), findsNothing);
    });

    testWidgets('a name in another case is still me', (tester) async {
      final rig = Rig(rows: [_sub(1, 'ALEX')]);
      final c = await boot(tester, rig);
      expect(c.canChange(c.rows.single), isTrue);
    });

    testWidgets("the organisation's own lists and the history are read only", (
      tester,
    ) async {
      for (final def in [
        _definition(system: 'branches'),
        _definition(isHistory: true),
      ]) {
        final rig = Rig(def: def);
        final c = await boot(tester, rig);
        expect(c.canAdd.value, isFalse);
        expect(c.canChange(c.rows.first), isFalse);
        expect(find.text('New record'), findsNothing);
        expect(find.bySemanticsLabel('Edit record 1'), findsNothing);
      }
    });
  });

  group('New record', () {
    testWidgets('opens the add form of #tstruct-add with the same arguments', (
      tester,
    ) async {
      final rig = Rig();
      final c = rig.controller(
        launch: const StructRecordsLaunch(
          name: 'leave',
          scope: 'user',
          caption: 'Leave request',
          convId: 'dm:ana',
          postChoiceTitle: 'Ana Lopez',
          isPostedByDefault: true,
        ),
      );
      await boot(tester, rig, controller: c);
      await tester.tap(find.text('New record').first);
      await pumpFor(tester, 100);
      final (route, args) = rig.routes.single;
      expect(route, AppRoutes.form);
      final launch = args! as FormLaunch;
      expect(launch.name, 'leave');
      expect(launch.scope, 'user');
      expect(launch.caption, 'Leave request');
      expect(launch.mode, FormMode.create);
      expect(launch.submissionId, isNull);
      expect(launch.convId, 'dm:ana');
      expect(launch.postChoiceTitle, 'Ana Lopez');
      expect(launch.isPostedByDefault, isTrue);
    });

    testWidgets('a saved record reads the list again', (tester) async {
      final rig = Rig()..routeResult = true;
      final c = await boot(tester, rig);
      final before = rig.listCalls;
      await c.addRecord();
      await pumpFor(tester, 100);
      expect(rig.listCalls, greaterThan(before));
    });

    testWidgets('a form closed without saving reads nothing', (tester) async {
      final rig = Rig();
      final c = await boot(tester, rig);
      final before = rig.listCalls;
      await c.addRecord();
      await pumpFor(tester, 100);
      expect(rig.listCalls, before);
    });
  });

  group('Edit', () {
    testWidgets('opens the app edit form with the saved values, then reads '
        'the list again', (tester) async {
      final rig = Rig()..routeResult = true;
      final c = await boot(tester, rig);
      final before = rig.listCalls;
      unawaited(c.editRecord(c.rows.first));
      await pumpFor(tester, 200);
      final (route, args) = rig.routes.single;
      expect(route, AppRoutes.form);
      final launch = args! as FormLaunch;
      expect(launch.mode, FormMode.edit);
      expect(launch.submissionId, '${c.rows.first.id}');
      expect(launch.savedValues?['kind'], c.rows.first.values['kind']);
      expect(rig.listCalls, greaterThan(before));
    });

    testWidgets('a record I may not change opens no form', (tester) async {
      final rig = Rig(rows: [_sub(2, 'maya')]);
      final c = await boot(tester, rig);
      await c.editRecord(c.rows.single);
      expect(rig.routes, isEmpty);
    });
  });

  group('Delete', () {
    testWidgets('asks first in the web words; Cancel deletes nothing', (
      tester,
    ) async {
      final rig = Rig();
      await boot(tester, rig);
      await tester.tap(find.bySemanticsLabel('Delete record 1'));
      await pumpFor(tester, 700);
      expect(find.text('Delete this record?'), findsOneWidget);
      expect(
        find.text(
          "Record #1 will be permanently deleted. This can't be undone.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await pumpFor(tester, 700);
      expect(rig.deleted, isEmpty);
      expect(find.text('No. 1'), findsOneWidget);
    });

    testWidgets('Delete removes the row only after the server said yes', (
      tester,
    ) async {
      final rig = Rig();
      final c = await boot(tester, rig);
      await tester.tap(find.bySemanticsLabel('Delete record 1'));
      await pumpFor(tester, 700);
      await tester.tap(find.text('Delete').last);
      await pumpFor(tester, 700);
      expect(rig.deleted, ['1']);
      expect(c.rows.map((r) => r.id), [2, 3]);
      expect(c.total.value, 2);
      expect(find.text('No. 1'), findsNothing);
    });

    testWidgets('a refusal keeps the row (forbidden, locked, rate limit)', (
      tester,
    ) async {
      final rig = Rig();
      final c = await boot(tester, rig);
      for (final words in [
        'Only the person who submitted it can delete it.',
        "It can't be deleted while it waits for approval or after it was "
            'approved.',
        'Too many requests. Try again in a moment.',
      ]) {
        rig.deleteAnswer = words;
        await c.deleteRecord(c.rows.first);
        expect(c.rows, hasLength(3), reason: words);
      }
      expect(rig.deleted, hasLength(3));
      expect(rig.local.calls, 0);
    });

    testWidgets('a record already gone leaves the list', (tester) async {
      final rig = Rig()..deleteAnswer = 'That submission no longer exists.';
      final c = await boot(tester, rig);
      await c.deleteRecord(c.rows.first);
      expect(c.rows.map((r) => r.id), [2, 3]);
    });

    testWidgets('the last record gone shows the empty state', (tester) async {
      final rig = Rig(rows: [_sub(1, 'alex')]);
      final c = await boot(tester, rig);
      await c.deleteRecord(c.rows.single);
      expect(c.viewState.value, AppViewState.empty);
    });
  });

  group('states', () {
    testWidgets('empty: No records yet and New record', (tester) async {
      final rig = Rig(rows: []);
      final c = await boot(tester, rig);
      expect(c.viewState.value, AppViewState.empty);
      expect(find.text('No records yet'), findsOneWidget);
      expect(find.text('New record'), findsWidgets);
    });

    testWidgets('error shows Retry and a retry loads', (tester) async {
      final rig = Rig()..failure = const SocketCallError('boom');
      final c = await boot(tester, rig);
      expect(c.viewState.value, AppViewState.error);
      rig.failure = null;
      await c.retry();
      expect(c.viewState.value, AppViewState.content);
    });

    testWidgets('offline: a calm message with Retry, nothing is asked', (
      tester,
    ) async {
      final rig = Rig()..isOnline = false;
      final c = await boot(tester, rig);
      expect(c.viewState.value, AppViewState.offline);
      expect(rig.listCalls, 0);
      rig.isOnline = true;
      await c.retry();
      expect(c.viewState.value, AppViewState.content);
    });

    testWidgets('a connection drop on refresh keeps what is shown', (
      tester,
    ) async {
      final rig = Rig();
      final c = await boot(tester, rig);
      rig.failure = const SocketCallError('timeout');
      await c.refreshList();
      expect(c.viewState.value, AppViewState.content);
      expect(c.rows, hasLength(3));
    });

    testWidgets('a structure that cannot be opened is an error', (
      tester,
    ) async {
      final rig = Rig(def: {'caption': 'x', 'fields': []});
      final c = await boot(tester, rig);
      expect(c.viewState.value, AppViewState.error);
    });
  });

  group('paging', () {
    testWidgets('loads 50 at a time and the rest at the end, no duplicates', (
      tester,
    ) async {
      final rig = Rig(rows: [for (var i = 1; i <= 120; i++) _sub(i, 'maya')]);
      final c = await boot(tester, rig);
      expect(c.rows, hasLength(50));
      expect(c.total.value, 120);
      expect(c.hasMore.value, isTrue);
      await c.loadMore();
      await c.loadMore();
      expect(c.rows, hasLength(120));
      expect(c.rows.map((r) => r.id).toSet(), hasLength(120));
      expect(c.hasMore.value, isFalse);
      final offsets = [for (final a in rig.asked) a['offset']];
      expect(offsets, containsAll([50, 100]));
      final before = rig.listCalls;
      await c.loadMore();
      expect(rig.listCalls, before);
    });
  });

  group('hidden fields', () {
    testWidgets('never drawn for a person who did not make the structure', (
      tester,
    ) async {
      final rig = Rig();
      final c = await boot(tester, rig);
      expect(c.view!.source.fieldOf('secret'), isNull);
      expect(find.text('Salary note'), findsNothing);
      expect(find.textContaining('S-1'), findsNothing);
      expect(find.textContaining('S-2'), findsNothing);
    });

    testWidgets('a hidden key field is not read for the title', (tester) async {
      final rig = Rig(
        def: {..._definition(), 'keyField': 'secret'},
        rows: [_sub(1, 'maya')],
      );
      await boot(tester, rig);
      expect(find.textContaining('S-1'), findsNothing);
    });

    test('shown to the structure creator and to an administrator', () {
      for (final (isCreator, isAdmin) in [(true, false), (false, true)]) {
        final v = StructRecordsSchema.of(
          FormDefinition.fromMap('leave', 'user', _definition()),
          isCreator: isCreator,
          isAdmin: isAdmin,
        );
        expect(v.source.fieldOf('secret'), isNotNull);
      }
      final other = StructRecordsSchema.of(
        FormDefinition.fromMap('leave', 'user', _definition()),
        isCreator: false,
        isAdmin: false,
      );
      expect(other.source.fieldOf('secret'), isNull);
    });

    testWidgets('the creator sees the hidden field', (tester) async {
      final rig = Rig(def: _definition(owner: 'alex'));
      await boot(tester, rig);
      expect(find.text('Salary note'), findsWidgets);
      expect(find.text('S-1'), findsOneWidget);
    });
  });

  group('tap on a row', () {
    testWidgets('does nothing: no route, no call, the local store untouched', (
      tester,
    ) async {
      final rig = Rig();
      await boot(tester, rig);
      final calls = rig.listCalls;
      final definitions = rig.definitionCalls;
      await tester.tap(find.text('No. 2'));
      await pumpFor(tester, 300);
      await tester.tap(find.text('No. 1'));
      await pumpFor(tester, 300);
      expect(rig.routes, isEmpty);
      expect(rig.listCalls, calls);
      expect(rig.definitionCalls, definitions);
      expect(rig.deleted, isEmpty);
      expect(rig.local.calls, 0);
    });
  });

  group('goldens', () {
    Future<void> shoot(WidgetTester tester, String name) async {
      tester.view.physicalSize = const Size(390, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('tstruct_records_loaded', (tester) async {
      await shoot(tester, 'loaded');
      final rig = Rig(
        rows: [
          _sub(1, 'alex'),
          _sub(2, 'maya'),
          _sub(3, 'alex', status: 'pending', ts: 2000000),
          _sub(4, 'alex', status: 'rejected', ts: 1500000),
        ],
      );
      await boot(tester, rig);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tstruct_records_loaded.png'),
      );
    });

    testWidgets('tstruct_records_empty', (tester) async {
      await shoot(tester, 'empty');
      await boot(tester, Rig(rows: []));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/tstruct_records_empty.png'),
      );
    });
  });

  test('a row parsed from submissions.list keeps the creator and status', () {
    final row = SvRow.tryParse(
      _sub(5, 'alex', status: 'pending'),
      isReceived: false,
    )!;
    expect(row.by, 'alex');
    expect(row.recordStatus, 'pending');
  });
}
