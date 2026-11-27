import 'dart:async';

import 'package:connectum/core/widgets/animated_callout_menu.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:connectum/features/tickets/models/card_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tickets/ticket_fixtures.dart';
import 'inbox_screen_support.dart';

const _items = [
  CardMenuItem('act-send', 'Send', Icons.send_rounded),
  CardMenuItem('act-status', 'Update status', Icons.sync_alt_rounded),
  CardMenuItem(CardMenuItem.history, 'History', Icons.history_rounded),
];

final _row = InboxRow(
  id: 24,
  formId: 't',
  form: 'Thing',
  subject: 'A thing',
  holder: 'ana',
  raiser: 'ana',
  ts: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> picked;

  setUp(() => picked = []);

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 800),
    double scale = 1,
    Alignment at = Alignment.topRight,
    List<CardMenuItem> items = _items,
    Future<void> Function(BuildContext context)? onTap,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: Align(
              alignment: at,
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: onTap == null
                      ? () async {
                          final item =
                              await AnimatedCalloutMenu.show<CardMenuItem>(
                                context,
                                AnimatedCalloutMenu.anchorOf(context)!,
                                InboxMenu.rowsFor(items),
                                label: 'Record menu',
                              );
                          if (item != null) picked.add(item.id);
                        }
                      : () => onTap(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
  }

  Finder rowOf(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell));

  testWidgets('rows are at least 44 px and icons share one left edge', (
    tester,
  ) async {
    await open(tester);
    for (final t in ['Send', 'Update status', 'History']) {
      expect(tester.getSize(rowOf(t)).height, greaterThanOrEqualTo(44));
    }
    final lefts = {
      for (final i in [
        Icons.send_rounded,
        Icons.sync_alt_rounded,
        Icons.history_rounded,
      ])
        tester.getTopLeft(find.byIcon(i)).dx,
    };
    expect(lefts.length, 1);
    expect(
      lefts.first - tester.getTopLeft(rowOf('Send')).dx,
      greaterThanOrEqualTo(12),
    );
  });

  testWidgets('no divider between normal rows, one above a danger row', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(Divider), findsNothing);
    await tester.tapAt(const Offset(4, 400));
    await tester.pumpAndSettle();
    await open(
      tester,
      items: const [
        CardMenuItem('act-send', 'Send', Icons.send_rounded),
        CardMenuItem(
          CardMenuItem.delete,
          'Delete',
          Icons.delete_rounded,
          isDanger: true,
        ),
      ],
    );
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('opens down with the right edge on the button', (tester) async {
    await open(tester);
    final button = tester.getRect(find.byIcon(Icons.more_horiz));
    final r = tester.getRect(rowOf('Send'));
    expect(r.top, greaterThanOrEqualTo(button.bottom));
    expect(r.right, closeTo(button.right + 4, 12));
  });

  testWidgets('flips up near the bottom and never covers the button', (
    tester,
  ) async {
    await open(tester, at: Alignment.bottomRight);
    final button = tester.getRect(find.byIcon(Icons.more_horiz));
    expect(
      tester.getRect(rowOf('History')).bottom,
      lessThanOrEqualTo(button.top),
    );
  });

  testWidgets('stays on screen at 320 px', (tester) async {
    await open(tester, size: const Size(320, 640), at: Alignment.topLeft);
    final r = tester.getRect(rowOf('Send'));
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(320));
  });

  testWidgets('text scale 1.5 does not overflow', (tester) async {
    await open(tester, size: const Size(320, 640), scale: 1.5);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(rowOf('Send')).width, lessThanOrEqualTo(320));
  });

  testWidgets('a row that is off shows the reason and does nothing', (
    tester,
  ) async {
    await open(
      tester,
      items: const [
        CardMenuItem(
          'act-send',
          'Send',
          Icons.send_rounded,
          isEnabled: false,
          why: 'Only the person it is with can do this.',
        ),
        CardMenuItem(CardMenuItem.history, 'History', Icons.history_rounded),
      ],
    );
    expect(
      find.text('Only the person it is with can do this.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('semantics list the items in order', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    for (final t in ['Send', 'Update status', 'History']) {
      expect(find.bySemanticsLabel(t), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('closes on outside tap and on back', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(4, 600));
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('every item reports its own id and closes the menu', (
    tester,
  ) async {
    for (final item in _items) {
      await open(tester);
      await tester.tap(find.text(item.label));
      await tester.pumpAndSettle();
      expect(picked.last, item.id);
      expect(find.text(item.label), findsNothing);
    }
    expect(picked, [for (final i in _items) i.id]);
  });

  testWidgets('the real menu says Loading… while it reads, then lists rows', (
    tester,
  ) async {
    final rig = InboxRig();
    addTearDown(rig.dispose);
    final release = Completer<void>();
    rig.routes[RecordCmd.actions] = (_) async {
      await release.future;
      return fixtureData('record_actions');
    };
    await open(
      tester,
      onTap: (context) => InboxMenu.show(context, rig.controller, _row),
    );
    expect(find.text('Loading…'), findsOneWidget);
    expect(find.text('Send'), findsNothing);
    release.complete();
    await tester.pumpAndSettle();
    expect(find.text('Loading…'), findsNothing);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Update status'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    await tester.tapAt(const Offset(4, 600));
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('golden: the card menu', (tester) async {
    await open(
      tester,
      size: const Size(390, 300),
      items: const [
        ..._items,
        CardMenuItem(
          CardMenuItem.delete,
          'Delete',
          Icons.delete_outline_rounded,
          isDanger: true,
        ),
      ],
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/inbox_compact_menu.png'),
    );
  });
}
