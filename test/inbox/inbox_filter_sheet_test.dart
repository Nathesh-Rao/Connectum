import 'dart:async';

import 'package:connectum/features/inbox/inbox_filter_controller.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/widgets/inbox_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';

Map<String, dynamic> facets() => {
  'submissions': <Object>[],
  'structures': <String, Object>{},
  'total': 0,
  'formCounts': {'t': 2, 'longform': 1},
  'people': {
    'createdBy': ['me', 'ravi'],
    'sentBy': ['sana'],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  Completer<Map<String, dynamic>>? held;
  InboxFilter? applied;
  var isCleared = false;

  /// Lets the wait of the panel and the socket run, then draws.
  Future<void> answered(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  /// The Add chip of a line is below the fold in a short window.
  Future<void> tapAdd(WidgetTester t, String label) async {
    final add = find.byKey(ValueKey('filter-add-$label'));
    await t.ensureVisible(add);
    await t.pump();
    await t.tap(add);
  }

  Future<InboxFilterController> pump(
    WidgetTester tester, {
    double width = 390,
    double height = 800,
    double scale = 1,
    InboxFilter initial = InboxFilter.none,
    bool isTeam = true,
    bool isHeld = false,
  }) async {
    rig = InboxRig();
    held = isHeld ? Completer<Map<String, dynamic>>() : null;
    rig.routes['records.query'] = (a) => a['facets'] == true
        ? (held?.future ?? Future.value(facets()))
        : queryReply([record(1)]);
    rig.routes['records.people'] = (_) => {
      'team': ['rhea', 'a_user_with_a_rather_long_name'],
      'sentBy': ['sana'],
      'sentTo': ['ravi'],
    };
    applied = null;
    isCleared = false;
    final panel = InboxFilterController(
      inbox: rig.inbox,
      initial: initial,
      baseWhere: 'me',
      isTeamShown: isTeam,
      forms: const {
        't': 'Thing',
        'longform': 'A form with a really quite long caption indeed',
      },
      onApply: (f) => applied = f,
      onClear: () => isCleared = true,
      wait: const Duration(milliseconds: 1),
    )..onInit();
    addTearDown(() {
      panel.onClose();
      rig.dispose();
    });
    tester.view.physicalSize = Size(width, height);
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
          body: SafeArea(child: InboxFilterPanel(panel: panel)),
        ),
      ),
    );
    await answered(tester);
    return panel;
  }

  testWidgets('shows every line of the web panel with its labels', (t) async {
    await pump(t);
    for (final s in [
      'Filters',
      'Where and what',
      'People',
      'Date and order',
      'Search in',
      'Data',
      'Created by',
      'Sent by',
      'Sent to',
      'Tagged to',
      'Date',
      'From date',
      'To date',
      'Sort',
      'Advanced filter',
      'Apply',
      'Clear',
    ]) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    expect(find.text('Open only'), findsOneWidget);
    expect(find.text('Closed only'), findsOneWidget);
    expect(find.text('Ascending (A to Z)'), findsOneWidget);
  });

  testWidgets(
    'Data shows counts once the server answered, never the full list first',
    (t) async {
      final p = await pump(t, isHeld: true);
      expect(p.formChoices, isEmpty, reason: 'counting: nothing offered yet');
      expect(find.text('Counting the forms...'), findsOneWidget);
      held!.complete(facets());
      await answered(t);
      expect(find.text('Counting the forms...'), findsNothing);
      await tapAdd(t, 'Data');
      await t.pumpAndSettle();
      expect(find.text('Thing (2)'), findsOneWidget);
      expect(
        find.text('A form with a really quite long caption indeed (1)'),
        findsOneWidget,
      );
    },
  );

  testWidgets('another Search in counts again and shows the counting text', (
    t,
  ) async {
    final p = await pump(t);
    expect(find.text('Counting the forms...'), findsNothing);
    held = Completer<Map<String, dynamic>>();
    p.setWheres(['completed']);
    await answered(t);
    expect(find.text('Counting the forms...'), findsOneWidget);
    held!.complete(facets());
    await answered(t);
    expect(find.text('Counting the forms...'), findsNothing);
  });

  testWidgets('choosing in a list, then Apply, hands the draft over', (
    t,
  ) async {
    final p = await pump(t);
    await tapAdd(t, 'Data');
    await t.pumpAndSettle();
    await t.tap(find.text('Thing (2)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Open only'));
    await t.pump();
    await t.tap(find.text('Open only'));
    await t.pump();
    expect(p.draft.value.forms, ['t']);
    expect(p.draft.value.status, 'open');
    expect(find.byKey(const ValueKey('filter-remove-Data-t')), findsOneWidget);
    await t.tap(find.text('Apply'));
    await t.pump();
    expect(applied?.forms, ['t']);
    expect(applied?.status, 'open');
    expect(isCleared, isFalse);
  });

  testWidgets('a list can be searched', (t) async {
    await pump(t);
    await tapAdd(t, 'Created by');
    await t.pumpAndSettle();
    expect(find.text('Me'), findsWidgets);
    await t.enterText(find.byType(TextField), 'zzz');
    await t.pump();
    expect(find.text('No match.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'rav');
    await t.pump();
    expect(find.text('ravi'), findsOneWidget);
  });

  testWidgets('Clear tells the Inbox to clear', (t) async {
    await pump(t);
    await t.tap(find.text('Clear'));
    await t.pump();
    expect(isCleared, isTrue);
    expect(applied, isNull);
  });

  testWidgets('Advanced opens a block; blocks stop at ten', (t) async {
    final p = await pump(t, height: 900);
    await t.ensureVisible(find.text('Advanced filter'));
    await t.tap(find.text('Advanced filter'));
    await t.pumpAndSettle();
    expect(p.draft.value.blocks.length, 1);
    expect(find.text('Data 1'), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      p.addBlock();
    }
    await t.pump();
    expect(p.draft.value.blocks.length, 10);
    expect(p.canAddBlock, isFalse);
  });

  group('small screen, big text', () {
    testWidgets(
      '320 px wide at text scale 1.5: no overflow, every line reachable',
      (t) async {
        final p = await pump(
          t,
          width: 320,
          height: 640,
          scale: 1.5,
          initial: InboxFilter(
            wheres: const ['me', 'requests', 'completed', 'escalations'],
            forms: const ['longform'],
            createdBy: const ['a_user_with_a_rather_long_name', 'me'],
            from: '2026-11-01',
            to: '2026-11-24',
            blocks: [
              InboxBlock(
                forms: const ['longform', 't'],
                createdBy: const ['a_user_with_a_rather_long_name'],
              ),
            ],
          ),
        );
        expect(t.takeException(), isNull);
        p.isAdvanced.value = true;
        await t.pump();
        expect(t.takeException(), isNull);
        // scroll to the end: the Advanced fold and the footer are reachable
        await t.dragUntilVisible(
          find.text('Add more data'),
          find.byType(SingleChildScrollView),
          const Offset(0, -200),
        );
        expect(t.takeException(), isNull);
        expect(find.text('Apply'), findsOneWidget);
        expect(find.text('Clear'), findsOneWidget);
        // the nested list and the date picker open without overflow too
        await t.tap(find.text('Add more data'));
        await t.pump();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('the multi-select sheet at 320 px, scale 1.5', (t) async {
      await pump(t, width: 320, height: 640, scale: 1.5);
      await tapAdd(t, 'Data');
      await t.pumpAndSettle();
      expect(find.text('Thing (2)'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      await tapAdd(t, 'Created by');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
