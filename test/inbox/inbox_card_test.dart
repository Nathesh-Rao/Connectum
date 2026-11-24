import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tickets/ticket_fixtures.dart';
import 'inbox_screen_support.dart';

InboxRow rowOf(Map<String, dynamic> raw) =>
    InboxRow.tryParse(raw, InboxForm.parseAll(structures))!;

Map<String, dynamic> values({
  String stage = 'Open',
  String? priority,
  Map<String, dynamic> more = const {},
}) => {
  'title': 'Laptop request',
  'stage': stage,
  'priority': ?priority,
  ...more,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  Future<void> pumpCard(
    WidgetTester tester,
    InboxRow row, {
    double width = 390,
    double scale = 1,
    int settleMs = 1500,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: RepaintBoundary(
              key: const ValueKey('golden'),
              child: Align(
                alignment: Alignment.topCenter,
                child: InboxCard(controller: rig.controller, row: row),
              ),
            ),
          ),
        ),
      ),
    );
    for (var t = 0; t < settleMs; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder band(AppTone tone) => find.byWidgetPredicate(
    (w) => w is ColoredBox && w.color == tone.tintMedium,
  );

  setUp(() {
    rig = InboxRig();
    rig.controller.onInit();
    addTearDown(rig.dispose);
  });

  final states = <String, ({InboxRow row, AppTone tone, String chip})>{
    'completed': (
      row: rowOf(record(1, values: values(stage: 'Done'))),
      tone: AppTones.green,
      chip: 'Done',
    ),
    'rejected': (
      row: rowOf(record(2, status: 'rejected', values: values())),
      tone: AppTones.red,
      chip: 'Open',
    ),
    'waiting': (
      row: rowOf(record(3, status: 'pending', values: values(stage: ''))),
      tone: AppTones.violet,
      chip: 'Waiting for approval',
    ),
    'pending': (
      row: rowOf(record(4, values: values(priority: 'High'))),
      tone: AppTones.yellow,
      chip: 'Open',
    ),
    'assigned': (
      row: rowOf(record(5, holder: 'ben', values: values())),
      tone: AppTones.blue,
      chip: 'Open',
    ),
  };

  for (final e in states.entries) {
    testWidgets('a ${e.key} card has its colour, title, number and chip', (
      tester,
    ) async {
      await pumpCard(tester, e.value.row);
      expect(band(e.value.tone), findsOneWidget);
      for (final other in states.entries.where((o) => o.key != e.key)) {
        if (other.value.tone != e.value.tone) {
          expect(band(other.value.tone), findsNothing);
        }
      }
      expect(find.text('Thing'), findsOneWidget);
      expect(find.textContaining('#${e.value.row.id} · '), findsOneWidget);
      expect(find.text(e.value.chip), findsWidgets);
      expect(find.text('Laptop request'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('goldens/inbox_card_${e.key}.png'),
      );
    });
  }

  testWidgets('the person: "You" for me, the user name until people.cards '
      'answers, then the name', (tester) async {
    rig.routes['records.query'] = (_) => queryReply([]);
    rig.routes['people.cards'] = (_) => {
      'people': {
        'ben': {'name': 'Ben Rao', 'avatar': ''},
      },
    };
    await pumpCard(tester, states['assigned']!.row, settleMs: 0);
    expect(find.text('ben'), findsOneWidget);
    await tester.runAsync(() => rig.inbox.loadCards(['ben']));
    await tester.pump();
    expect(find.text('Ben Rao'), findsOneWidget);
    expect(find.text('ben'), findsNothing);
  });

  testWidgets('"You" when the card is about me', (tester) async {
    await pumpCard(tester, states['pending']!.row);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('a priority dot says its level', (tester) async {
    await pumpCard(tester, states['pending']!.row);
    expect(find.byTooltip('High priority'), findsOneWidget);
    final dot = tester.widget<Container>(
      find.descendant(
        of: find.byType(Tooltip),
        matching: find.byType(Container),
      ),
    );
    expect(
      (dot.decoration as BoxDecoration).color,
      AppTones.red.solid,
    );
  });

  testWidgets('no dot without a priority', (tester) async {
    await pumpCard(tester, states['assigned']!.row);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('the body lists answers and leaves empty ones out', (
    tester,
  ) async {
    final row = rowOf(
      record(
        6,
        values: values(more: {'note': '   ', 'room': 'B12', 'cost': 12.0}),
        labels: {'room': 'Block B, 12'},
      ),
    );
    await pumpCard(tester, row);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('room'), findsOneWidget);
    expect(find.text('Block B, 12'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('note'), findsNothing);
    expect(find.text('Stage'), findsNothing);
  });

  testWidgets('no menu when record.actions allows nothing', (tester) async {
    await pumpCard(tester, states['pending']!.row);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('the menu shows when record.actions allows an action', (
    tester,
  ) async {
    rig.routes['record.actions'] = (_) => fixtureData('record_actions');
    await pumpCard(tester, states['pending']!.row, settleMs: 3000);
    expect(rig.asked, contains('record.actions'));
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('320 px wide at text scale $scale does not overflow', (
      tester,
    ) async {
      final long = rowOf(
        record(
          7,
          holder: 'a.very.long.user.name',
          values: values(
            stage: 'Pending: waiting for action from the finance team',
            priority: 'High',
            more: {
              'title': 'A very long title that cannot fit on one line at all',
              'description': List.filled(30, 'long text').join(' '),
            },
          ),
        ),
      );
      for (final row in [long, ...states.values.map((s) => s.row)]) {
        await pumpCard(tester, row, width: 320, scale: scale, settleMs: 200);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
