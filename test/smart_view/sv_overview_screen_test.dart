import 'dart:async';

import 'package:connectum/core/theme/app_sv.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/overview/sv_overview.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/smart_view/models/sv_overview_model.dart';
import 'package:connectum/features/smart_view/widgets/sv_overview_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sv_support.dart';

final _now = DateTime(2026, 11, 18, 12);

SvRow _row(int id, DateTime at, {String stage = 'Open', String status = ''}) =>
    SvRow(
      id: id,
      tstruct: 's',
      by: 'me',
      ts: at.millisecondsSinceEpoch,
      recordStatus: status,
      values: {'stage': stage},
    );

SvSource _source(String name, {bool hasStatus = true}) => SvSource(
  name: name,
  caption: 'Struct $name',
  fields: const [
    SvField(name: 'stage', caption: 'Stage'),
    SvField(name: 'title', caption: 'Title'),
  ],
  table: hasStatus ? const TicketTable(field: 'stage') : null,
);

Future<void> pumpFor(WidgetTester tester, [int ms = 700]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> host(
    WidgetTester tester,
    SvOverviewModel model, {
    bool isEmpty = false,
    void Function(SvSource)? onOpen,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 844),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SvOverviewBody(
              model: model,
              isEmpty: isEmpty,
              onOpen: onOpen ?? (_) {},
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );
  }

  SvOverviewModel fake(
    Map<String, SvOverviewRead Function()> by, {
    Completer<void>? gate,
  }) => SvOverviewModel(
    clock: () => _now,
    read: (s) async {
      if (gate != null) await gate.future;
      return by[s.name]!();
    },
  );

  SvOverviewRead rich() => SvOverviewRead(
    isOk: true,
    total: 120,
    rows: [
      for (var i = 0; i < 40; i++)
        _row(
          i,
          _now.subtract(Duration(hours: 5 * i + 3)),
          stage: i % 3 == 0 ? 'Done' : (i % 3 == 1 ? 'Open' : 'Blocked'),
          status: i % 9 == 0 ? 'pending' : '',
        ),
    ],
  );

  testWidgets('four KPI tiles of one size; numbers once everything settled', (
    tester,
  ) async {
    final model = fake({
      'a': rich,
      'b': () => const SvOverviewRead(isOk: true),
    });
    await host(tester, model);
    unawaited(model.start([_source('a'), _source('b')]));
    await pumpFor(tester, 1500);
    Size tile(String label) => tester.getSize(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );
    final sizes = {
      for (final l in const [
        'Structures',
        'Records',
        'This week',
        'Waiting for approval',
      ])
        l: tile(l),
    };
    expect(sizes.values.toSet().length, 1, reason: '$sizes');
    expect(find.text('120'), findsWidgets);
    expect(model.records, 120);
    expect(model.week, 12);
    expect(model.pending, 5);
  });

  testWidgets('Waiting for approval is hidden without an approval source', (
    tester,
  ) async {
    final model = fake({
      'a': () => SvOverviewRead(
        isOk: true,
        total: 2,
        rows: [_row(1, _now), _row(2, _now)],
      ),
    });
    await host(tester, model);
    unawaited(model.start([_source('a', hasStatus: false)]));
    await pumpFor(tester, 1500);
    expect(find.text('Waiting for approval'), findsNothing);
    expect(find.text('Structures'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
  });

  testWidgets('skeletons and "…" while loading, numbers after', (tester) async {
    final gate = Completer<void>();
    final model = fake({'a': rich, 'b': rich}, gate: gate);
    await host(tester, model);
    unawaited(model.start([_source('a'), _source('b')]));
    await pumpFor(tester, 800);
    expect(
      find.byKey(const ValueKey('sv-overview-skeleton')),
      findsNWidgets(2),
    );
    expect(find.text('…'), findsWidgets);
    expect(find.text('Updating…'), findsOneWidget);
    gate.complete();
    await pumpFor(tester, 1500);
    expect(find.byKey(const ValueKey('sv-overview-skeleton')), findsNothing);
    expect(find.text('Updated just now'), findsOneWidget);
    expect(find.text('Last entry 3 h ago'), findsWidgets);
  });

  testWidgets('an error card says so and Retry reads that structure again', (
    tester,
  ) async {
    var tries = 0;
    final model = fake({
      'a': rich,
      'b': () {
        tries++;
        return tries == 1 ? const SvOverviewRead(isOk: false) : rich();
      },
    });
    await host(tester, model);
    unawaited(model.start([_source('a'), _source('b')]));
    await pumpFor(tester, 1500);
    expect(find.text("Couldn't load"), findsOneWidget);
    expect(find.text(SvOverviewBody.partialNote), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await pumpFor(tester, 1500);
    expect(tries, 2);
    expect(find.text("Couldn't load"), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a tap on a card opens that structure; an error card does not', (
    tester,
  ) async {
    final opened = <String>[];
    final model = fake({
      'a': rich,
      'b': () => const SvOverviewRead(isOk: false),
    });
    await host(tester, model, onOpen: (s) => opened.add(s.name));
    unawaited(model.start([_source('a'), _source('b')]));
    await pumpFor(tester, 1500);
    await tester.tap(find.text('Struct a'));
    await pumpFor(tester, 300);
    await tester.tap(find.text('Struct b'));
    await pumpFor(tester, 300);
    expect(opened, ['a']);
  });

  testWidgets('empty: a calm block, no tiles', (tester) async {
    final model = fake({});
    await host(tester, model, isEmpty: true);
    await pumpFor(tester, 300);
    expect(find.text('No smart views yet'), findsOneWidget);
    expect(find.text('Records'), findsNothing);
  });

  testWidgets('a card: count, bars, mix legend with "+N more", footer', (
    tester,
  ) async {
    final model = SvOverviewModel(
      clock: () => _now,
      read: (s) async => SvOverviewRead(
        isOk: true,
        total: 1234,
        rows: [
          for (var i = 0; i < 10; i++)
            _row(i, _now.subtract(Duration(hours: i)), stage: 'S${i % 5}'),
        ],
      ),
    );
    await host(tester, model);
    unawaited(model.start([_source('a')]));
    await pumpFor(tester, 1500);
    expect(find.text('1,234'), findsWidgets);
    expect(find.text('records'), findsOneWidget);
    expect(find.text('2 fields'), findsOneWidget);
    expect(find.text('+2 more'), findsOneWidget);
    expect(find.text('Last entry just now'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Records in the last seven days')),
      findsOneWidget,
    );
  });

  for (final w in const [320.0, 390.0]) {
    testWidgets('no overflow at $w dp and text scale 1.3', (tester) async {
      final model = fake({
        'a': rich,
        'b': () => const SvOverviewRead(isOk: false),
        'c': () => const SvOverviewRead(isOk: true),
      });
      await host(tester, model, width: w, scale: 1.3);
      unawaited(model.start([_source('a'), _source('b'), _source('c')]));
      await pumpFor(tester, 1500);
      expect(tester.takeException(), isNull);
    });
  }

  group('goldens', () {
    testWidgets('sv_overview_loaded', (tester) async {
      final model = fake({
        'a': rich,
        'b': () => const SvOverviewRead(isOk: true),
        'c': () => const SvOverviewRead(isOk: false),
      });
      await host(tester, model);
      unawaited(model.start([_source('a'), _source('b'), _source('c')]));
      await pumpFor(tester, 2000);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_overview_loaded.png'),
      );
    });

    testWidgets('sv_overview_loading', (tester) async {
      final model = fake({'a': rich, 'b': rich}, gate: Completer<void>());
      await host(tester, model, scale: 1);
      unawaited(model.start([_source('a'), _source('b')]));
      await pumpFor(tester, 1500);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_overview_loading.png'),
      );
    });

    testWidgets('sv_overview_empty', (tester) async {
      await host(tester, fake({}), isEmpty: true);
      await pumpFor(tester, 300);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_overview_empty.png'),
      );
    });
  });

  group('the read goes through the gate', () {
    test(
      'one list per structure, never over 6 in 10 s, 300 ms apart',
      () async {
        final rig = SvRig();
        addTearDown(() {
          rig.tickets.onClose();
          rig.repo.onClose();
        });
        const n = 14;
        final names = [for (var i = 0; i < n; i++) 's$i'];
        rig.socket.answers[SvCmd.sources] = {
          'forms': [
            for (final s in names)
              {
                'name': s,
                'caption': s,
                'fields': [
                  {'name': 'title', 'caption': 'Title', 'type': 'text'},
                ],
              },
          ],
        };
        final at = <DateTime>[];
        final asked = <String>[];
        rig.socket.answers['submissions.list'] = (Map<String, dynamic> args) {
          at.add(rig.clock.now);
          asked.add('${args['tstruct']}:${args['limit']}:${args['offset']}');
          return {
            'submissions': [
              ownRow(1, tstruct: '${args['tstruct']}', values: {'title': 'x'}),
            ],
            'total': 900,
            'hasMore': true,
          };
        };
        final model = SvOverviewModel(
          clock: rig.clock.read,
          read: rig.repo.readForOverview,
        );
        final sources = await rig.repo.sources();
        final start = rig.clock.now;
        await model.start(sources);
        expect(asked.length, n, reason: 'one page of 500 per structure');
        expect(asked.every((a) => a.endsWith(':500:0')), isTrue);
        expect(rig.count('records.mine'), 0, reason: 'own records only');
        for (var i = 0; i < at.length; i++) {
          if (i > 0) {
            expect(
              at[i].difference(at[i - 1]).inMilliseconds,
              greaterThanOrEqualTo(300),
            );
          }
          final inWindow = at
              .where(
                (t) =>
                    !t.isBefore(at[i]) && t.difference(at[i]) < SvLimits.window,
              )
              .length;
          expect(inWindow, lessThanOrEqualTo(SvLimits.budget));
        }
        expect(model.isSettled, isTrue);
        expect(model.cards.every((c) => c.stats.value!.count == 900), isTrue);
        expect(model.isPartial, isTrue, reason: 'the newest 500 only');
        final total = rig.clock.now.difference(start);
        // 14 structures at 6 per 10 s: three windows, about 20 s of waiting.
        expect(total.inSeconds, inInclusiveRange(15, 30));
        expect(rig.repo.keptSources, isNotNull);
        expect(AppSv.ovStagger.inMilliseconds, 60);
      },
    );

    test('a failing read only fails its own card', () async {
      final rig = SvRig();
      addTearDown(() {
        rig.tickets.onClose();
        rig.repo.onClose();
      });
      rig.socket.answers[SvCmd.sources] = {
        'forms': [
          for (final s in const ['a', 'b'])
            {'name': s, 'caption': s, 'fields': <Object>[]},
        ],
      };
      Map<String, dynamic> answer(Map<String, dynamic> args) {
        if (args['tstruct'] == 'a') {
          throw const SocketCallError('error', 'boom');
        }
        return {'submissions': <Object>[], 'total': 0, 'hasMore': false};
      }

      rig.socket.answers['submissions.list'] = answer;
      final model = SvOverviewModel(
        clock: rig.clock.read,
        read: rig.repo.readForOverview,
      );
      await model.start(await rig.repo.sources());
      expect(model.cards[0].phase.value, SvCardPhase.error);
      expect(model.cards[1].phase.value, SvCardPhase.ready);
      expect(model.cards[1].stats.value!.count, 0);
      expect(
        SvOverview.lastEntry(model.cards[1].stats.value!.lastTs, _now),
        'No records yet',
      );
    });
  });
}
