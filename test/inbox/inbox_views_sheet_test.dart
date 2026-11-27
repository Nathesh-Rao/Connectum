import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_views_controller.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_saved_view.dart';
import 'package:connectum/features/inbox/widgets/inbox_view_dialogs.dart';
import 'package:connectum/features/inbox/widgets/inbox_views_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';

Map<String, dynamic> sv(String name) => {
  'name': name,
  'view': {'folder': 'data'},
  'savedTs': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  const longName = 'A very long view name that wraps over lines';

  Future<void> pump(
    WidgetTester t, {
    double width = 320,
    double scale = 1.5,
    List<String> names = const ['Alpha', longName, 'Gamma'],
    bool isOnline = true,
    String? def,
    String open = '',
    Widget? body,
  }) async {
    rig = InboxRig(isOnline: isOnline);
    addTearDown(rig.dispose);
    rig.routes['inbox.views.get'] = (_) => {
      'views': [for (final n in names) sv(n)],
      'default': def,
    };
    final c = rig.controller;
    c.views.kept.value = InboxSetup.keyOf(InboxSetup.plain());
    rig.viewsRepo.views.assignAll([
      for (final n in names) InboxSavedView(name: n, setup: const {}),
    ]);
    rig.viewsRepo.defaultName.value = def;
    rig.viewsRepo.isReady.value = true;
    c.views.current.value = open;
    t.view.physicalSize = Size(width, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                body ??
                Center(
                  child: TextButton(
                    onPressed: () => InboxViewsSheet.show(context, c),
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester t) async {
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  group('the Views sheet', () {
    testWidgets('320 px, text scale 1.5: no overflow, every action reachable', (
      t,
    ) async {
      await pump(t, def: 'Alpha', open: longName);
      await openSheet(t);
      expect(t.takeException(), isNull);
      expect(find.text('Default View'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text(longName), findsWidgets);
      expect(
        find.text('Default'),
        findsOneWidget,
        reason: 'the default is tagged',
      );
      for (final label in [
        'Save view',
        'Save as new view',
        'Create view',
        'Set as default',
        'Remove view',
      ]) {
        await t.dragUntilVisible(
          find.text(label),
          find.byType(SingleChildScrollView).first,
          const Offset(0, -80),
        );
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('the Default View is first and the open view is marked', (
      t,
    ) async {
      await pump(t, open: 'Alpha');
      await openSheet(t);
      final top = t.getTopLeft(find.text('Default View')).dy;
      expect(top, lessThan(t.getTopLeft(find.text('Alpha')).dy));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final mark = t.getCenter(find.byIcon(Icons.check_rounded)).dy;
      expect((mark - t.getCenter(find.text('Alpha')).dy).abs(), lessThan(12));
    });

    testWidgets('the Default View has no Set as default and no Remove', (
      t,
    ) async {
      await pump(t);
      await openSheet(t);
      expect(find.text('Remove view'), findsNothing);
      expect(find.text('Set as default'), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('a default view offers Clear default', (t) async {
      await pump(t, def: 'Alpha', open: 'Alpha');
      await openSheet(t);
      expect(find.text('Clear default'), findsOneWidget);
    });

    testWidgets(
      'offline: the last list shows, saving is off and a note says so',
      (t) async {
        await pump(t, isOnline: false, open: 'Alpha');
        rig.connectivity.set(AppConnectivity.offline);
        await openSheet(t);
        expect(find.text(InboxViews.offlineNote), findsOneWidget);
        expect(find.text('Alpha'), findsOneWidget);
        await t.dragUntilVisible(
          find.text('Save view'),
          find.byType(SingleChildScrollView).first,
          const Offset(0, -80),
        );
        await t.tap(find.text('Save view'));
        await t.pump();
        expect(
          rig.asked.where((a) => a.startsWith('inbox.views.save')),
          isEmpty,
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('a failed read shows a line with Retry', (t) async {
      await pump(t);
      rig.routes['inbox.views.get'] = (_) =>
          throw const SocketCallError('timeout');
      await openSheet(t);
      expect(find.text(InboxViews.loadError), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget, reason: 'the last list stays');
    });
  });

  group('the name dialog', () {
    Future<void> openDialog(WidgetTester t, {bool isNew = true}) async {
      await pump(t, names: const ['Alpha', 'Beta']);
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.dragUntilVisible(
        find.text('Save as new view'),
        find.byType(SingleChildScrollView).first,
        const Offset(0, -80),
      );
      await t.tap(find.text('Save as new view'));
      await t.pumpAndSettle();
    }

    testWidgets('an empty, a reserved and a taken name each say why', (
      t,
    ) async {
      await openDialog(t);
      expect(find.text('Save as new view'), findsWidgets);
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      expect(find.text(InboxViewRules.empty), findsOneWidget);
      await t.enterText(find.byType(TextField), 'default VIEW');
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      expect(find.text(InboxViewRules.reserved), findsOneWidget);
      await t.enterText(find.byType(TextField), 'alpha');
      await t.pump();
      expect(
        find.text(InboxViewRules.reserved),
        findsNothing,
        reason: 'typing clears it',
      );
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      expect(find.text(InboxViewRules.taken), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('twenty views: a new name says at most 20', (t) async {
      await pump(t, names: [for (var i = 0; i < 20; i++) 'V$i']);
      await openSheet(t);
      await t.dragUntilVisible(
        find.text('Save as new view'),
        find.byType(SingleChildScrollView).first,
        const Offset(0, -80),
      );
      await t.tap(find.text('Save as new view'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'One more');
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      expect(find.text(InboxViewRules.tooMany), findsOneWidget);
    });

    testWidgets('the dialog fits 320 px at text scale 1.5', (t) async {
      await openDialog(t);
      await t.tap(find.text('Save').last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('the other dialogs', () {
    testWidgets(
      '"Save your changes?" at 320 px, scale 1.5, with its three answers',
      (t) async {
        await pump(
          t,
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => InboxUnsavedDialog.ask(context),
              child: const Text('ask'),
            ),
          ),
        );
        await t.tap(find.text('ask'));
        await t.pumpAndSettle();
        expect(find.text('Save your changes?'), findsOneWidget);
        for (final s in ['Save', 'Discard', 'Cancel']) {
          expect(find.text(s), findsOneWidget, reason: s);
        }
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('Remove asks first, with the name', (t) async {
      await pump(
        t,
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => InboxRemoveDialog.ask(context, longName),
            child: const Text('ask'),
          ),
        ),
      );
      await t.tap(find.text('ask'));
      await t.pumpAndSettle();
      expect(find.textContaining('Remove the view'), findsOneWidget);
      expect(find.text('Remove view'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('the Views button marker', () {
    test('a changed screen is marked, a saved one is not', () async {
      rig = InboxRig();
      addTearDown(rig.dispose);
      final c = rig.controller;
      c.views.kept.value = InboxSetup.keyOf(InboxSetup.plain());
      expect(c.isViewChanged, isFalse);
      c.filter.value = const InboxFilter(forms: ['x']);
      expect(c.isViewChanged, isTrue);
    });
  });
}
