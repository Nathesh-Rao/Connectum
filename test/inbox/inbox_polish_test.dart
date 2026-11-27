import 'package:connectum/core/widgets/app_text_field.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/widgets/inbox_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';

Map<String, dynamic> _req(int id) => {
  'id': id,
  'type': 'submission',
  'status': 'pending',
  'from': 'rhea',
  'fromName': 'Rhea Rao',
  'approvers': ['ana'],
  'direction': 'incoming',
  'canRespond': true,
  'createdTs': DateTime(2026, 11, 20, 9, id).millisecondsSinceEpoch,
  'data': {
    'caption': 'Expense $id',
    'tstruct': 'expense',
    'stage': 1,
    'stages': 2,
    'summary': [
      {'caption': 'Amount', 'value': '120'},
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<InboxRig> pump(
    WidgetTester t, {
    double width = 390,
    double height = 900,
    double scale = 1,
    double keyboard = 0,
    int records = 3,
    int? total,
    bool isCapped = false,
  }) async {
    final rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (a) => a['facets'] == true
        ? {
            'submissions': <Object>[],
            'structures': <String, Object>{},
            'total': 0,
            'formCounts': {'t': 2},
            'people': {
              'createdBy': ['me', 'ravi'],
            },
          }
        : queryReply(
            [for (var i = records; i > 0; i--) record(i)],
            total: total,
            capped: isCapped,
          );
    rig.routes['req.list'] = (_) => {
      'requests': [_req(1)],
      'total': 1,
      'hasMore': false,
    };
    Get.put(rig.controller);
    addTearDown(Get.reset);
    t.view.physicalSize = Size(width, height);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: const InboxView(),
      ),
    );
    await settle(t);
    return rig;
  }

  final pill = find.byKey(const ValueKey('inbox-records-count'));

  List<InboxIconButton> buttons(WidgetTester t) =>
      t.widgetList<InboxIconButton>(find.byType(InboxIconButton)).toList();

  group('header', () {
    testWidgets('no mail icon; the views chip sits in the title row', (
      t,
    ) async {
      await pump(t);
      expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
      final title = t.getRect(find.text('Inbox'));
      final chip = t.getRect(find.byIcon(Icons.filter_center_focus_rounded));
      final search = t.getRect(find.byTooltip('Search'));
      expect(chip.left, greaterThan(title.right));
      expect(chip.right, lessThan(search.left));
      expect((chip.center.dy - title.center.dy).abs(), lessThan(8));
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('the close button is outside the field and folds the bar', (
      t,
    ) async {
      final rig = await pump(t);
      await t.tap(find.byTooltip('Search'));
      await settle(t);
      expect(rig.controller.isSearchOpen.value, isTrue);
      final field = t.getRect(find.byType(AppTextField));
      final close = find.byKey(const ValueKey('inbox-search-close'));
      expect(close, findsOneWidget);
      expect(t.getRect(close).left, greaterThanOrEqualTo(field.right));
      expect(t.getRect(close).width, greaterThanOrEqualTo(40));
      expect(t.getRect(close).height, greaterThanOrEqualTo(40));
      expect(
        find.descendant(
          of: find.byType(AppTextField),
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AppTextField),
          matching: find.byIcon(Icons.search_rounded),
        ),
        findsOneWidget,
      );
      await t.enterText(find.byType(TextField), 'abc');
      await t.tap(close);
      await settle(t);
      expect(rig.controller.isSearchOpen.value, isFalse);
    });

    testWidgets('the search and the filter buttons have different tones', (
      t,
    ) async {
      await pump(t);
      final b = buttons(t);
      expect(b.length, 2);
      expect(b[0].tone.solid, isNot(b[1].tone.solid));
      expect(b[0].tone.tint, isNot(b[1].tone.tint));
    });

    testWidgets(
      'the filter button turns accent and counts while a filter is on',
      (t) async {
        final rig = await pump(t);
        expect(buttons(t)[1].isActive, isFalse);
        expect(buttons(t)[1].count, 0);
        rig.controller.applyFilter(const InboxFilter(forms: ['t']));
        await settle(t);
        final filter = buttons(t)[1];
        expect(filter.isActive, isTrue);
        expect(filter.count, 1);
        expect(
          find.descendant(of: find.byWidget(filter), matching: find.text('1')),
          findsOneWidget,
        );
        expect(buttons(t)[0].isActive, isFalse);
      },
    );

    testWidgets('no separate records line is drawn', (t) async {
      await pump(t);
      expect(find.text('3 records'), findsNothing);
    });
  });

  group('the Records tab count', () {
    testWidgets('shows the total after the label', (t) async {
      await pump(t);
      expect(
        find.descendant(of: pill, matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('a capped total reads N+', (t) async {
      await pump(t, total: 1001, isCapped: true);
      expect(
        find.descendant(of: pill, matching: find.text('1000+')),
        findsOneWidget,
      );
    });

    testWidgets('a filtered list shows the filtered total', (t) async {
      final rig = await pump(t, records: 2, total: 7);
      rig.controller.applyFilter(const InboxFilter(forms: ['t']));
      await settle(t);
      expect(
        find.descendant(of: pill, matching: find.text('7')),
        findsOneWidget,
      );
    });

    testWidgets('a list of approvals alone has no records count', (t) async {
      final rig = await pump(t);
      rig.controller.applyFilter(const InboxFilter(wheres: ['approvals']));
      await settle(t);
      expect(pill, findsNothing);
    });

    testWidgets('the Records pill never shows the approvals count', (t) async {
      await pump(t);
      expect(find.byKey(const ValueKey('inbox-records-count')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('inbox-records-count')),
          matching: find.text('1'),
        ),
        findsNothing,
      );
    });

    testWidgets('320 px at text scale 1.5: no overflow, the label stays', (
      t,
    ) async {
      await pump(t, width: 320, scale: 1.5, total: 1001, isCapped: true);
      expect(t.takeException(), isNull);
      expect(find.text('Records'), findsOneWidget);
      expect(find.text('Approvals'), findsOneWidget);
      // The test font is wider than Space Grotesk, so the label may be cut
      // here; the order is what counts: the icon goes first, then the label
      // is cut, and the pill stays inside its tab and compact.
      expect(find.byIcon(Icons.inbox_outlined), findsNothing);
      expect(find.byIcon(Icons.inbox_rounded), findsNothing);
      final label = t.getRect(find.text('Records'));
      final thumb = t.getRect(find.byKey(const ValueKey('inbox-tab-thumb')));
      final p = t.getRect(pill);
      expect(label.width, greaterThan(0));
      expect(p.right, lessThanOrEqualTo(thumb.right + 0.5));
      expect(p.height, lessThan(30 * 1.5));
      expect(label.right, lessThanOrEqualTo(p.left));
    });
  });

  group('the filter popup', () {
    Future<void> open(WidgetTester t) async {
      await t.tap(find.byIcon(Icons.tune_rounded));
      await settle(t);
    }

    testWidgets('has the three section cards and the Advanced fold', (t) async {
      await pump(t);
      await open(t);
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
        'Sort',
        'Advanced filter',
        'Apply',
        'Clear',
      ]) {
        expect(find.text(s), findsWidgets, reason: s);
      }
    });

    testWidgets('Apply hands the draft over and closes the popup', (t) async {
      final rig = await pump(t);
      await open(t);
      await t.ensureVisible(find.text('Open only'));
      await t.pump();
      await t.tap(find.text('Open only'));
      await t.pump();
      await t.tap(find.text('Apply'));
      await settle(t);
      expect(find.text('Filters'), findsNothing);
      expect(rig.controller.filterCount, greaterThan(0));
    });

    testWidgets('a tap outside drops the draft', (t) async {
      final rig = await pump(t);
      await open(t);
      await t.ensureVisible(find.text('Open only'));
      await t.pump();
      await t.tap(find.text('Open only'));
      await t.pump();
      await settle(t);
      await t.tapAt(const Offset(2, 880));
      await settle(t);
      expect(find.text('Filters'), findsNothing);
      expect(rig.controller.filterCount, 0);
    });

    testWidgets('Clear closes the popup and clears the filter', (t) async {
      final rig = await pump(t);
      rig.controller.applyFilter(const InboxFilter(forms: ['t']));
      await settle(t);
      await open(t);
      await t.tap(find.text('Clear'));
      await settle(t);
      expect(find.text('Filters'), findsNothing);
      expect(rig.controller.filterCount, 0);
    });

    testWidgets(
      'a form is added from the searchable list and removed as a chip',
      (t) async {
        await pump(t);
        await open(t);
        await t.tap(find.byKey(const ValueKey('filter-add-Data')));
        await settle(t);
        expect(find.byType(TextField), findsOneWidget);
        await t.tap(find.text('Thing (2)'));
        await t.pump();
        await t.tap(find.text('Done'));
        await settle(t);
        final chip = find.byKey(const ValueKey('filter-remove-Data-t'));
        expect(chip, findsOneWidget);
        expect(
          find.byKey(const ValueKey('filter-count-Where and what')),
          findsOneWidget,
        );
        await t.tap(chip);
        await settle(t);
        expect(chip, findsNothing);
        await t.tap(find.byTooltip('Close the filters'));
        await settle(t);
      },
    );

    testWidgets('320 px, text scale 1.5, keyboard open: it fits', (t) async {
      await pump(t, width: 320, height: 640, scale: 1.5, keyboard: 280);
      await open(t);
      expect(t.takeException(), isNull);
      final apply = t.getRect(find.text('Apply'));
      expect(apply.bottom, lessThanOrEqualTo(640 - 280));
      expect(apply.left, greaterThanOrEqualTo(0));
      expect(apply.right, lessThanOrEqualTo(320));
      final add = find.byKey(const ValueKey('filter-add-Created by'));
      await t.ensureVisible(add);
      await t.pump();
      await t.tap(add);
      await settle(t);
      expect(t.takeException(), isNull);
    });
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
