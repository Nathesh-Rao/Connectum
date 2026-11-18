import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/sv_saved_views_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/data/smart_view/sv_saved_view.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:connectum/features/smart_view/widgets/sv_columns_sheet.dart';
import 'package:connectum/features/smart_view/widgets/sv_group_by_sheet.dart';
import 'package:connectum/features/smart_view/widgets/sv_save_view_sheet.dart';
import 'package:connectum/features/tickets/ticket_detail_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

// Fakes only: an in-memory server for `smartview.views`, no network, no
// phone (DevGuard is for the integration tests). Bounded pumps.

class _Connectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The server's list of one person's views of one source.
class _Server {
  List<Map<String, Object?>> list = [];
  int reads = 0;
  int writes = 0;
  bool failRead = false;
  bool forbid = false;
  void Function()? beforeRead;

  Future<Map<String, dynamic>> call(
    String cmd,
    Map<String, dynamic> args,
  ) async {
    if (cmd == 'smartview.views') {
      reads++;
      beforeRead?.call();
      if (failRead) throw const SocketCallError('error');
      return {
        'mine': [for (final v in list) Map<String, Object?>.of(v)],
        'shared': <Object?>[],
        'canPublish': false,
      };
    }
    writes++;
    if (forbid) throw const SocketCallError('forbidden');
    list = [
      for (final v in args['views'] as List)
        Map<String, Object?>.from(v as Map),
    ];
    return {'views': list};
  }
}

Map<String, Object?> _view(
  String id,
  String name, {
  List<Object?> filters = const [],
  List<String> groupBy = const [],
  List<String> hidden = const [],
  List<String> order = const [],
  Map<String, Object?> extra = const {},
}) => {
  ...extra,
  'id': id,
  'name': name,
  'search': '',
  'filters': filters,
  'sort': null,
  'groupBy': groupBy,
  'hidden': hidden,
  'order': order,
  'widths': <String, Object?>{},
  'kpis': true,
  'charts': true,
};

const _titles = [
  ('Printer jammed', 'Delivery', '2026-11-20', 2.5, 'Open'),
  ('Router down', 'Billing', '2026-10-02', 4, 'In progress'),
  ('Alpha invoice', 'Billing', '', 1, 'Closed'),
  ('Laptop request', 'Delivery', '2026-12-05', 8, 'Open'),
  ('Badge lost', 'Support', '2026-11-02', 3, 'Open'),
  ('Zeta audit', 'Support', '2026-11-30', 12, 'Closed'),
];

List<SvRow> _rows() => [
  for (var i = 0; i < _titles.length; i++)
    SvRow.tryParse({
      'id': i + 1,
      'by': 'svcapcpw1ann',
      'byName': 'Ann Rao',
      'ts': 1794833216000 + i * 60000,
      'tstruct': 'tickets',
      'canEdit': true,
      'values': {
        'title': _titles[i].$1,
        'area': _titles[i].$2,
        'due': _titles[i].$3,
        'hours': _titles[i].$4,
        'stage': _titles[i].$5,
        'secret': 'HIDDEN-VALUE-123',
      },
    }, isReceived: false)!,
];

class _NoSubmissions extends GetxService implements SubmissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- model ----------------------------------------------------------------

  group('model', () {
    test('every fixture round-trips with its unknown keys', () {
      final dir = Directory('test/fixtures/smart_view/views');
      final files = dir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json'),
      );
      expect(files, isNotEmpty);
      for (final f in files) {
        final raw = jsonDecode(f.readAsStringSync());
        final maps = raw is List ? raw : [raw];
        for (final m in maps) {
          if (m is! Map || m['id'] is! String) continue;
          final v = SvSavedView.tryParse(m)!;
          final back = jsonDecode(jsonEncode(v.toJson())) as Map;
          for (final e in m.entries) {
            if (e.key == 'sort' || e.key == 'groupBy') continue;
            expect(back[e.key], e.value, reason: '${f.path} ${e.key}');
          }
        }
      }
    });

    test('unknown keys are kept and written back untouched', () {
      final v = SvSavedView.tryParse({
        ..._view('a', 'A'),
        'wrapAll': true,
        'future': {'x': 1},
      })!;
      final out = v.toJson();
      expect(out['wrapAll'], true);
      expect(out['future'], {'x': 1});
      expect(v.sameAs(SvSavedView.tryParse(out)), isTrue);
    });

    test('a legacy single groupBy string reads as one level', () {
      final v = SvSavedView.tryParse({
        'id': 'a',
        'name': 'A',
        'groupBy': 'stage',
      })!;
      expect(v.groupBy, ['stage']);
      expect(SvSavedView.tryParse({'name': 'no id'}), isNull);
    });

    test('hidden fields never reach the screen state or a saved view', () {
      final v = SvSavedView.tryParse(
        _view(
          'a',
          'A',
          filters: [
            {'col': 'secret', 'op': 'contains', 'value': 'x'},
            {
              'col': 'stage',
              'op': 'in',
              'value': ['Open'],
            },
            {'col': 'area', 'op': 'is', 'value': 'x', 'preset': true},
          ],
          groupBy: ['secret', 'area'],
        ),
      )!;
      final st = v.toState({'stage', 'area', 'title'});
      expect([for (final c in st.query.conditions) c.col], ['stage']);
      expect(st.groupBy, ['area']);
      final back = v.withState(st).toJson();
      expect(jsonEncode(back), isNot(contains('secret')));
    });

    test('web keys map to the app columns and back', () {
      expect(SvKeys.mobile('By'), SmartViewColumns.byKey);
      expect(SvKeys.web(SmartViewColumns.submittedKey), 'On');
      expect(SvKeys.mobile('stage'), 'stage');
    });
  });

  // ---- repository: merge, conflict, failures ---------------------------------

  group('repository', () {
    late _Server server;
    late SvSavedViewsRepository repo;
    setUp(() {
      server = _Server()
        ..list = [_view('a', 'Open only'), _view('b', 'By area')];
      repo = SvSavedViewsRepository(call: server.call);
    });

    SvSavedView parse(Map<String, Object?> m) => SvSavedView.tryParse(m)!;

    test(
      'save merges by id: our change applied, another device\'s kept',
      () async {
        final seen = parse(server.list[0]);
        // another device adds C and changes B after we loaded
        server.list = [_view('c', 'Theirs'), ...server.list];
        server.list[2] = _view('b', 'By area', groupBy: ['area']);
        final out = await repo.apply(
          'tickets',
          SvViewChange.update(seen.copyWith(name: 'Renamed')),
          seen: seen,
        );
        expect(out.isSaved, isTrue);
        expect([for (final v in server.list) v['id']], ['c', 'a', 'b']);
        expect(server.list[1]['name'], 'Renamed');
        expect(server.list[2]['groupBy'], ['area']);
        expect(server.reads, 1);
        expect(server.writes, 1);
      },
    );

    test('a new view goes first; a name that exists is refused', () async {
      final out = await repo.apply(
        'tickets',
        SvViewChange.add(SvSavedView.fresh('n1', 'Mine', SvViewState.plain)),
      );
      expect(out.isSaved, isTrue);
      expect(server.list.first['id'], 'n1');
      final dup = await repo.apply(
        'tickets',
        SvViewChange.add(SvSavedView.fresh('n2', 'mine', SvViewState.plain)),
      );
      expect(dup.status, SvSaveStatus.invalid);
      final taken = await repo.apply(
        'tickets',
        SvViewChange.add(
          SvSavedView.fresh('n3', 'default view', SvViewState.plain),
        ),
      );
      expect(taken.status, SvSaveStatus.invalid);
    });

    test('a view changed remotely asks first; overwrite writes', () async {
      final seen = parse(server.list[0]);
      server.list[0] = _view('a', 'Open only', groupBy: ['stage']);
      final mine = seen.withState(const SvViewState(groupBy: ['area']));
      final out = await repo.apply(
        'tickets',
        SvViewChange.update(mine),
        seen: seen,
      );
      expect(out.status, SvSaveStatus.conflict);
      expect(server.writes, 0);
      final over = await repo.apply(
        'tickets',
        SvViewChange.update(mine),
        seen: seen,
        isOverwrite: true,
      );
      expect(over.isSaved, isTrue);
      expect(server.list[0]['groupBy'], ['area']);
    });

    test('a view removed remotely is a conflict for an update', () async {
      final seen = parse(server.list[0]);
      server.list.removeAt(0);
      final out = await repo.apply(
        'tickets',
        SvViewChange.update(seen.copyWith(name: 'X')),
        seen: seen,
      );
      expect(out.status, SvSaveStatus.conflict);
    });

    test('a failed re-read saves nothing', () async {
      server.failRead = true;
      final out = await repo.apply(
        'tickets',
        SvViewChange.remove('a'),
        seen: parse(server.list[0]),
      );
      expect(out.status, SvSaveStatus.readFailed);
      expect(server.writes, 0);
    });

    test('forbidden and the 20-view limit', () async {
      server.forbid = true;
      final f = await repo.apply(
        'tickets',
        SvViewChange.add(SvSavedView.fresh('z', 'Z', SvViewState.plain)),
      );
      expect(f.status, SvSaveStatus.forbidden);
      server
        ..forbid = false
        ..list = [for (var i = 0; i < 20; i++) _view('v$i', 'View $i')];
      final l = await repo.apply(
        'tickets',
        SvViewChange.add(SvSavedView.fresh('z', 'Z', SvViewState.plain)),
      );
      expect(l.status, SvSaveStatus.invalid);
    });

    test(
      'remove deletes only that id; web-only keys elsewhere survive',
      () async {
        server.list[1] = _view('b', 'By area', extra: {'webOnly': 1});
        final out = await repo.apply(
          'tickets',
          SvViewChange.remove('a'),
          seen: parse(server.list[0]),
        );
        expect(out.isSaved, isTrue);
        expect([for (final v in server.list) v['id']], ['b']);
        expect(server.list[0]['webOnly'], 1);
      },
    );
  });

  // ---- controller and screens ------------------------------------------------

  group('screen', () {
    late SvRig rig;
    late SmartViewController c;
    late _Server server;

    void init({bool forbid = false}) {
      Get.reset();
      rig = SvRig();
      server = _Server()
        ..forbid = forbid
        ..list = [
          _view(
            'a',
            'Open only',
            filters: [
              {
                'col': 'stage',
                'op': 'in',
                'value': ['Open'],
              },
            ],
          ),
          _view('g', 'By area', groupBy: ['area']),
          _view('g2', 'Area then stage', groupBy: ['area', 'stage']),
          _view(
            'k',
            'Compact',
            hidden: ['due', 'hours'],
            order: ['stage', 'title'],
          ),
        ];
      Get.put<SmartViewRepository>(rig.repo);
      Get.put<TicketRepository>(rig.tickets);
      Get.put<SubmissionRepository>(_NoSubmissions());
      Get.put<FormFileRepository>(FakeFiles());
      Get.put<ConnectivityService>(_Connectivity());
      c = SmartViewController(
        repo: rig.repo,
        tickets: rig.tickets,
        submissions: Get.find<SubmissionRepository>(),
        prefs: SmartViewPrefs(),
        views: SvSavedViewsRepository(call: server.call),
        newTicketDetail: (id) => TicketDetailController(
          ticketId: id,
          tickets: rig.tickets,
          files: Get.find<FormFileRepository>(),
          connectivity: Get.find<ConnectivityService>(),
        ),
      );
      final s = sourceNamed('tickets');
      c.current.value = s;
      c.table.value = SvTable(s)
        ..rows.assignAll(_rows())
        ..phase.value = SvPhase.ready;
    }

    tearDown(() {
      rig.tickets.onClose();
      rig.repo.onClose();
      Get.reset();
    });

    void screen(
      String name,
      Future<void> Function(WidgetTester t) body, {
      bool forbid = false,
    }) => testWidgets(name, (tester) async {
      init(forbid: forbid);
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        GetMaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SmartViewContent(controller: c),
          ),
        ),
      );
      await c.openViews(sourceNamed('tickets'));
      await pumpFor(tester, 300);
      await body(tester);
    });

    Finder inCols(Finder f) =>
        find.descendant(of: find.byType(SvColumnsBody), matching: f);
    Finder inGroup(Finder f) =>
        find.descendant(of: find.byType(SvGroupByBody), matching: f);

    List<String> titles() => [
      for (final r in c.shownRows) '${r.values['title']}',
    ];

    screen('tabs: Default View first, saved views, then +', (t) async {
      expect(find.text('Default View'), findsOneWidget);
      expect(find.text('Open only'), findsOneWidget);
      expect([for (final v in c.tabs) v.name], contains('Compact'));
      expect(find.text('+'), findsWidgets);
      expect(c.selectedViewId.value, isNull);
      expect(c.isDirty, isFalse);
    });

    screen('selecting a tab applies its filter; Default View clears it', (
      t,
    ) async {
      await t.tap(find.text('Open only'));
      await pumpFor(t, 400);
      expect(titles(), ['Printer jammed', 'Laptop request', 'Badge lost']);
      expect(c.isDirty, isFalse);
      await t.tap(find.text('Default View'));
      await pumpFor(t, 400);
      expect(titles().length, 6);
    });

    screen('grouping: header counts, order of first appearance', (t) async {
      c.selectView('g');
      await pumpFor(t, 400);
      final g = c.grouped!;
      final heads = [
        for (final f in g.flat)
          if (f.isGroup) (f.group, f.count),
      ];
      expect(heads, [('Delivery', 2), ('Billing', 2), ('Support', 2)]);
      expect(g.flat.where((f) => !f.isGroup).length, 6);
      expect(find.text('Delivery'), findsWidgets);
    });

    screen('two group levels nest; counts are the rows inside', (t) async {
      c.selectView('g2');
      await pumpFor(t, 400);
      final g = c.grouped!;
      final top = g.flat.where((f) => f.isGroup && f.depth == 0).toList();
      final sub = g.flat.where((f) => f.isGroup && f.depth == 1).toList();
      expect([for (final f in top) f.count], [2, 2, 2]);
      expect(sub.fold<int>(0, (a, f) => a + f.count!), 6);
      // the engine's own result is what is drawn
      final input = c.engineInput!;
      final eng = SvEngine.group(
        input.table,
        input.orderedPositions(c.query.value),
        ['area', 'stage'],
        sumKey: input.measureKeys.firstOrNull,
      );
      expect(g.flat.length, eng.length);
      expect(g.sumLabel, 'Hours');
      final delivery = top.first;
      expect(delivery.sum, 10.5);
    });

    screen('collapse is kept per view', (t) async {
      c.selectView('g');
      await pumpFor(t, 300);
      final path = c.grouped!.flat.first.path!;
      c.toggleGroup(path);
      expect(c.grouped!.flat.where((f) => !f.isGroup).length, 4);
      c.selectView('g2');
      expect(c.closedGroups, isEmpty);
      c.selectView('g');
      expect(c.closedGroups, contains(path));
      expect(c.grouped!.flat.where((f) => !f.isGroup).length, 4);
    });

    screen('columns: hidden and order apply to cards and table', (t) async {
      c.selectView('k');
      await pumpFor(t, 400);
      final keys = [for (final x in c.shownColumns!.listable) x.key];
      expect(keys.first, 'stage');
      expect(keys[1], 'title');
      expect(keys, isNot(contains('due')));
      expect(keys, isNot(contains('hours')));
      final card = c.shownColumns!.cardOf(c.shownRows.first);
      expect([
        for (final f in card.fields) f.column.key,
      ], isNot(contains('due')));
      c.mode.value = SvViewMode.table;
      await pumpFor(t, 500);
      expect(find.text('Due'), findsNothing);
      expect(find.text('Area'), findsWidgets);
    });

    screen('a structure-hidden field is in no column, group or sheet', (
      t,
    ) async {
      expect(c.columns!.columns.where((x) => x.key == 'secret'), isEmpty);
      expect(c.shownColumns!.columns.where((x) => x.key == 'secret'), isEmpty);
      unawaited(
        SvColumnsSheet.show(t.element(find.byType(SmartViewContent)), c),
      );
      await pumpFor(t, 900);
      expect(find.text('Secret'), findsNothing);
      expect(find.text('Show hidden fields'), findsNothing);
    });

    screen('unsaved pill: Save writes that view only, Reset reverts', (
      t,
    ) async {
      c.selectView('a');
      await pumpFor(t, 300);
      expect(find.text('Unsaved changes'), findsNothing);
      c.setGroupBy(['area']);
      await pumpFor(t, 300);
      expect(find.text('Unsaved changes'), findsOneWidget);
      // Reset
      await t.ensureVisible(find.text('Reset'));
      await t.tap(find.text('Reset'));
      await pumpFor(t, 300);
      expect(c.isDirty, isFalse);
      expect(c.groupBy, isEmpty);
      // change again and Save
      c.setGroupBy(['stage']);
      await pumpFor(t, 300);
      await t.ensureVisible(find.text('Save'));
      await t.tap(find.text('Save'));
      await pumpFor(t, 500);
      expect(server.writes, 1);
      expect(server.list.firstWhere((v) => v['id'] == 'a')['groupBy'], [
        'stage',
      ]);
      expect(server.list.firstWhere((v) => v['id'] == 'g')['groupBy'], [
        'area',
      ]);
      expect(c.isDirty, isFalse);
      expect(find.text('Unsaved changes'), findsNothing);
    });

    screen('Default View: no Save, no manage sheet', (t) async {
      c.setGroupBy(['area']);
      await pumpFor(t, 300);
      expect(c.isDirty, isTrue);
      expect(c.canSave, isFalse);
      expect(find.text('Save'), findsNothing);
      await t.longPress(find.text('Default View'));
      await pumpFor(t, 500);
      expect(find.text('Rename'), findsNothing);
    });

    screen('manage: rename, duplicate, delete', (t) async {
      await t.ensureVisible(find.text('Compact'));
      await t.longPress(find.text('Compact'));
      await pumpFor(t, 600);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await c.renameView('k', 'Tiny');
      expect(server.list.any((v) => v['name'] == 'Tiny'), isTrue);
      await c.duplicateView('k');
      expect(
        server.list.where((v) => '${v['name']}'.startsWith('Tiny copy')),
        hasLength(1),
      );
      await c.deleteView('k');
      expect(server.list.any((v) => v['id'] == 'k'), isFalse);
      c.selectView('a');
      await c.deleteView('a');
      expect(c.selectedViewId.value, isNull);
    });

    screen('Save view sheet: needs a name, shows what it will keep', (t) async {
      c.setGroupBy(['area']);
      c.setConditions(const [
        SvCondition('stage', 'in', ['Open']),
      ]);
      await t.ensureVisible(find.text('+'));
      await t.tap(find.text('+'));
      await pumpFor(t, 900);
      expect(find.text('Save view'), findsOneWidget);
      expect(find.text('1 filter'), findsOneWidget);
      expect(find.textContaining('Group by: Area'), findsOneWidget);
      await t.tap(find.text('Save').last);
      await pumpFor(t, 300);
      expect(find.text('Give the view a name.'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, '  Fresh   one ');
      await t.tap(find.text('Save').last);
      await pumpFor(t, 800);
      expect(server.list.first['name'], 'Fresh one');
      expect(c.tabs.first.name, 'Fresh one');
      expect(c.selectedViewId.value, server.list.first['id']);
      expect(c.isDirty, isFalse);
    });

    screen('a view changed on another device asks; Reload drops ours', (
      t,
    ) async {
      c.selectView('g');
      c.setGroupBy(['stage']);
      server.beforeRead = () {
        final i = server.list.indexWhere((v) => v['id'] == 'g');
        server.list[i] = _view('g', 'By area', groupBy: ['area', 'stage']);
        server.beforeRead = null;
      };
      var asked = 0;
      c.askOverwrite = () async {
        asked++;
        return false;
      };
      expect(await c.saveCurrent(), isFalse);
      expect(asked, 1);
      expect(server.writes, 0);
      expect(c.groupBy.toList(), ['area', 'stage']);
      expect(c.isDirty, isFalse);
    });

    screen('Overwrite writes our version', (t) async {
      c.selectView('g');
      c.setGroupBy(['stage']);
      server.beforeRead = () {
        final i = server.list.indexWhere((v) => v['id'] == 'g');
        server.list[i] = _view('g', 'By area', groupBy: ['area', 'stage']);
        server.beforeRead = null;
      };
      c.askOverwrite = () async => true;
      expect(await c.saveCurrent(), isTrue);
      expect(server.list.firstWhere((v) => v['id'] == 'g')['groupBy'], [
        'stage',
      ]);
    });

    screen('failed views read: Default View and a retry pill', (t) async {
      server.failRead = true;
      c.tabs.clear();
      await c.retryViews();
      await pumpFor(t, 300);
      expect(c.viewsPhase.value, SvViewsPhase.error);
      expect(find.text('Default View'), findsOneWidget);
      expect(find.textContaining('Retry'), findsOneWidget);
      server.failRead = false;
      await c.retryViews();
      await pumpFor(t, 300);
      expect(find.text('Open only'), findsOneWidget);
    });

    screen('forbidden: a refused save hides + and the manage actions', (
      t,
    ) async {
      server.forbid = true;
      expect(await c.saveAsNew('Nope'), isFalse);
      await pumpFor(t, 300);
      expect(c.canWriteViews.value, isFalse);
      expect(find.text('+'), findsNothing);
      await t.ensureVisible(find.text('Compact'));
      await t.longPress(find.text('Compact'));
      await pumpFor(t, 500);
      expect(find.text('Rename'), findsNothing);
    });

    screen('golden: the view tabs with unsaved changes', (t) async {
      c.selectView('a');
      c.setGroupBy(['area']);
      await pumpFor(t, 500);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_view_tabs.png'),
      );
    });

    screen('golden: the save view sheet', (t) async {
      c.setGroupBy(['area']);
      await t.ensureVisible(find.text('+'));
      await t.tap(find.text('+'));
      await pumpFor(t, 900);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_save_view_sheet.png'),
      );
    });

    screen('golden: grouped cards', (t) async {
      c.selectView('g2');
      await pumpFor(t, 500);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_grouped_cards.png'),
      );
    });

    screen('golden: grouped table', (t) async {
      c.selectView('g');
      c.mode.value = SvViewMode.table;
      await pumpFor(t, 700);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_grouped_table.png'),
      );
    });

    screen('golden: the columns sheet', (t) async {
      unawaited(
        SvColumnsSheet.show(t.element(find.byType(SmartViewContent)), c),
      );
      await pumpFor(t, 900);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_columns_sheet.png'),
      );
    });

    screen('golden: the group by sheet', (t) async {
      c.setGroupBy(['area', 'stage']);
      unawaited(
        SvGroupBySheet.show(t.element(find.byType(SmartViewContent)), c),
      );
      await pumpFor(t, 900);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_group_by_sheet.png'),
      );
    });

    screen('columns sheet: Apply stores hidden and order; Reset restores', (
      t,
    ) async {
      unawaited(
        SvColumnsSheet.show(t.element(find.byType(SmartViewContent)), c),
      );
      await pumpFor(t, 900);
      await t.tap(inCols(find.text('Due')));
      await pumpFor(t, 200);
      await t.tap(inCols(find.text('Apply')));
      await pumpFor(t, 600);
      expect(c.hidden, contains('due'));
      expect(c.isDirty, isTrue);
      unawaited(
        SvColumnsSheet.show(t.element(find.byType(SmartViewContent)), c),
      );
      await pumpFor(t, 900);
      await t.tap(inCols(find.text('Reset')));
      await pumpFor(t, 200);
      await t.tap(inCols(find.text('Apply')));
      await pumpFor(t, 600);
      expect(c.hidden.where((h) => h == 'due'), isEmpty);
    });

    screen('group by sheet: tick order is the level order, Clear removes', (
      t,
    ) async {
      unawaited(
        SvGroupBySheet.show(t.element(find.byType(SmartViewContent)), c),
      );
      await pumpFor(t, 900);
      await t.tap(inGroup(find.text('Stage')));
      await t.tap(inGroup(find.text('Area')));
      await pumpFor(t, 200);
      await t.tap(inGroup(find.text('Apply')));
      await pumpFor(t, 600);
      expect(c.groupBy.toList(), ['stage', 'area']);
      unawaited(
        SvGroupBySheet.show(t.element(find.byType(SmartViewContent)), c),
      );
      await pumpFor(t, 900);
      await t.tap(inGroup(find.text('Clear')));
      await pumpFor(t, 600);
      expect(c.groupBy, isEmpty);
      expect(SvSaveViewSheet.summary(c).first, 'No filters');
    });
  });
}
