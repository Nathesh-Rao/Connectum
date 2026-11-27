import 'dart:async';

import 'package:connectum/core/tour/tour_action.dart';
import 'package:connectum/core/tour/tour_gesture.dart';
import 'package:connectum/core/tour/tour_id.dart';
import 'package:connectum/core/tour/tour_runner.dart';
import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/tour/widgets/tour_card_layer.dart';
import 'package:connectum/core/tour/tour_texts.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/smart_view/models/smart_view_entry.dart';
import 'package:connectum/features/smart_view/smart_view_binding.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_tour.dart';
import 'package:connectum/features/smart_view/smart_view_tour_demo.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_card.dart';
import 'package:connectum/features/smart_view/widgets/sv_filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../core/tour/tour_test_support.dart';
import '../support/fake_socket.dart';
import 'sv_support.dart';

class _Submissions extends GetxService implements SubmissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

enum _Exit { finish, skip, cancel, leaveTab }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFont);

  late SvRig rig;
  late TourService service;
  late SmartViewController c;
  late SmartViewTour tour;

  /// [views]: the person has views. [opens]: a view with rows is open.
  Future<void> boot(
    WidgetTester tester, {
    bool views = false,
    bool opens = false,
    double width = 390,
    double scale = 1,
    bool keepsDrawerOpen = false,
  }) async {
    Get.reset();
    rig = SvRig();
    service = TourService(userId: () => 'u1', store: memoryStore());
    await service.markSeen(TourId.chatList);
    rig.socket.answers[SvCmd.sources] = views
        ? captured('004')
        : <String, dynamic>{'forms': <dynamic>[]};
    rig.socket.answers['record.actions'] = captured('030');
    rig.socket.answers['submissions.list'] = listPager([
      ownRow(2, ts: 1794833216651),
      ownRow(1, ts: 1794833216000),
    ]);
    rig.socket.answers['records.mine'] = minePager({
      'with': <Map<String, dynamic>>[],
    }, pageSize: 50);
    Get.put<SmartViewRepository>(rig.repo);
    Get.put<TicketRepository>(rig.tickets);
    Get.put<SubmissionRepository>(_Submissions());
    Get.put<FormFileRepository>(FakeFiles());
    Get.put<ConnectivityService>(_Connectivity());
    Get.put<TourService>(service);
    addTearDown(() {
      rig.tickets.onClose();
      rig.repo.onClose();
      Get.reset();
    });
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SmartViewBinding().dependencies();
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: const SmartViewView(),
      ),
    );
    await tester.pump();
    c = Get.find<SmartViewController>();
    tour = c.tour!;
    unawaited(
      c.enter(
        opens
            ? const SmartViewEntry.named('tickets')
            : const SmartViewEntry.tab(),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The drawer opens by itself on the list. Shut before the tour's wait is
    // over, the tour finds it closed; left alone, it finds it open.
    if (!keepsDrawerOpen && c.isDrawerOpen.value) c.closeDrawer();
    for (var i = 0; i < 40 && !service.isActive.value; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpTour(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.text(TourTexts.next));
    await pumpTour(tester);
    await pumpTour(tester);
    expect(tester.takeException(), isNull);
  }

  void expectClean() {
    final d = tour.demo;
    expect(service.isActive.value, isFalse);
    expect(c.isDrawerOpen.value, isFalse);
    expect(c.isTourSampleShown, isFalse);
    expect(d.isDriving, isFalse);
    expect(d.isListSample.value, isFalse);
    expect(d.isRecordsSample.value, isFalse);
    expect(d.isFilterOpen.value, isFalse);
    expect(d.table, isNull);
    expect(c.expanded.where((id) => id < 0), isEmpty);
    expect(c.filesExpanded.where((id) => id < 0), isEmpty);
    expect(c.sources.where((s) => d.isSampleSource(s)), isEmpty);
  }

  group('the steps', () {
    test('seven at most, in order, each one run by an action', () {
      final t = SmartViewTour(
        service: TourService(userId: () => 'u1', store: memoryStore()),
      );
      final steps = t.steps(_ports(), isSample: true);
      expect(steps.length, lessThanOrEqualTo(7));
      expect(steps.map((s) => s.title), [
        TourTexts.svViewsTitle,
        TourTexts.svCardsTitle,
        TourTexts.svModeTitle,
        TourTexts.svSearchTitle,
        TourTexts.svFilterTitle,
        TourTexts.svActionsTitle,
        TourTexts.svExpandTitle,
      ]);
      expect(steps.map((s) => s.target), [
        t.drawerKey,
        t.cardKey,
        t.modeKey,
        t.searchKey,
        t.filterKey,
        t.fabKey,
        t.cardKey,
      ]);
      expect(steps.every((s) => s.actions.isNotEmpty), isTrue);
      // The pointer taps the menu, then a row of the drawer.
      expect(steps[0].actions.first.target, t.menuKey);
      expect(steps[0].actions.first.gesture, TourGesture.tap);
      expect(steps[1].actions[1].target, t.rowKey);
      expect(TourId.smartView.version, 2);
    });

    test('the button is named as it is: Actions, with what it holds', () {
      expect(TourTexts.svActionsBody, contains('Actions'));
      expect(TourTexts.svActionsBody, contains('Add record'));
      expect(TourTexts.svActionsBody, contains('KPI'));
      expect(TourTexts.svActionsBody, contains('Charts'));
    });
  });

  group('an account with no smart views', () {
    testWidgets('gets the tour on a sample view and sample records', (
      tester,
    ) async {
      await boot(tester);
      final asked = rig.socket.calls.length;
      final d = tour.demo;

      // 1. The drawer opens by itself and lists the sample view.
      expect(find.text(TourTexts.svViewsTitle), findsOneWidget);
      expect(c.isDrawerOpen.value, isTrue);
      expect(find.text(TourTexts.svSampleViewCaption), findsOneWidget);
      expect(find.text(TourTexts.sampleTag), findsOneWidget);
      expect(c.sources, isEmpty, reason: 'the list itself is untouched');

      // 2. The view is picked, the drawer closes, cards show.
      await next(tester);
      expect(find.text(TourTexts.svCardsTitle), findsOneWidget);
      expect(c.isDrawerOpen.value, isFalse);
      expect(c.isTourSampleShown, isTrue);
      expect(find.byType(SmartViewCard), findsNWidgets(3));
      expect(find.text('Quote-1042.pdf'), findsOneWidget, reason: 'file chip');
      expect(find.text(TourTexts.sampleTag), findsOneWidget, reason: 'header');
      expect(c.mode.value, SvViewMode.cards);

      // 3. Cards / Table, 4. Search.
      await next(tester);
      expect(find.text(TourTexts.svModeTitle), findsOneWidget);
      await next(tester);
      expect(find.text(TourTexts.svSearchTitle), findsOneWidget);

      // 5. Filter and Sort, with the filter sheet open for a moment.
      await next(tester);
      expect(find.text(TourTexts.svFilterTitle), findsOneWidget);
      expect(d.isFilterOpen.value, isTrue);
      expect(find.byType(SvFilterSheetBody), findsOneWidget);

      // 6. The Actions button; the sheet is gone.
      await next(tester);
      expect(find.text(TourTexts.svActionsTitle), findsOneWidget);
      expect(d.isFilterOpen.value, isFalse);
      expect(find.byType(SvFilterSheetBody), findsNothing);
      expect(find.byKey(tour.fabKey), findsOneWidget);

      // 7. A card opens, then closes with the tour.
      await next(tester);
      expect(find.text(TourTexts.svExpandTitle), findsOneWidget);
      expect(c.expanded, contains(-1));

      await tester.tap(find.text(TourTexts.done));
      await pumpTour(tester);
      await pumpTour(tester);
      expectClean();
      expect(c.table.value, isNull);
      expect(c.current.value, isNull);
      expect(find.byType(SmartViewCard), findsNothing);
      expect(rig.socket.calls.length, asked, reason: 'no read, no ReadGate');
      expect(await service.isSeen(TourId.smartView), isTrue);
      expect(tester.takeException(), isNull);
    });

    for (final how in _Exit.values) {
      testWidgets('restore runs on ${how.name}, with a card open', (
        tester,
      ) async {
        await boot(tester);
        c.setMode(SvViewMode.table);
        final asked = rig.socket.calls.length;
        for (var i = 0; i < 6; i++) {
          await next(tester);
        }
        expect(c.expanded, contains(-1));
        switch (how) {
          case _Exit.finish:
            await tester.tap(find.text(TourTexts.done));
          case _Exit.skip:
            await tester.tap(find.text(TourTexts.skip));
          case _Exit.cancel:
            service.cancel();
          case _Exit.leaveTab:
            c.setActive(false);
        }
        await pumpTour(tester);
        await pumpTour(tester);
        expectClean();
        expect(c.table.value, isNull);
        expect(c.mode.value, SvViewMode.table, reason: 'the choice is back');
        expect(rig.socket.calls.length, asked);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an exit on the first step closes the drawer', (tester) async {
      await boot(tester);
      expect(c.isDrawerOpen.value, isTrue);
      await tester.tap(find.text(TourTexts.skip));
      await pumpTour(tester);
      await pumpTour(tester);
      expectClean();
      expect(find.byType(SmartViewCard), findsNothing);
    });

    testWidgets('a sample record number is never a real one', (tester) async {
      await boot(tester);
      await next(tester);
      expect(c.table.value!.rows.every((r) => r.id < 0), isTrue);
      expect(c.shownRows.map((r) => r.id), [-1, -2, -3]);
      service.cancel();
      await pumpTour(tester);
    });
  });

  group('a drawer that is open when the tab shows', () {
    Rect freeArea(double width) => TourPlacement.freeArea(
      screen: Size(width, 844),
      insets: EdgeInsets.zero,
      barTop: null,
    );

    void expectButtonsHittable(WidgetTester tester, double width) {
      final free = freeArea(width);
      for (final label in [TourTexts.skip, TourTexts.next]) {
        final rect = tester.getRect(find.text(label));
        expect(rect.left, greaterThanOrEqualTo(0), reason: label);
        expect(rect.right, lessThanOrEqualTo(width), reason: label);
        expect(rect.top, greaterThanOrEqualTo(0), reason: label);
        expect(rect.bottom, lessThanOrEqualTo(free.bottom), reason: label);
      }
    }

    testWidgets('step 1 lights the open drawer and does nothing to it', (
      tester,
    ) async {
      await boot(tester, views: true, keepsDrawerOpen: true);
      expect(service.isActive.value, isTrue);
      expect(c.isDrawerOpen.value, isTrue);
      expect(find.text(TourTexts.svViewsTitle), findsOneWidget);
      final first = tour.steps(_ports(), isSample: true, isDrawerOpen: true);
      expect(first.first.actions, isEmpty);
      expect(first[1].actions.map((a) => a.kind), [
        TourActionKind.tapTarget,
        TourActionKind.closeDrawer,
      ]);
      service.cancel();
      await pumpTour(tester);
    });

    testWidgets('Skip and Next are on screen and work at 320 px, x1.5', (
      tester,
    ) async {
      await boot(
        tester,
        views: true,
        keepsDrawerOpen: true,
        width: 320,
        scale: 1.5,
      );
      expect(c.isDrawerOpen.value, isTrue);
      expectButtonsHittable(tester, 320);
      await next(tester);
      expect(find.text(TourTexts.svCardsTitle), findsOneWidget);
      expect(c.isDrawerOpen.value, isFalse);
      expectButtonsHittable(tester, 320);
      await tester.tap(find.text(TourTexts.skip));
      await pumpTour(tester);
      expect(service.isActive.value, isFalse);
      expect(tester.takeException(), isNull);
    });

    for (final how in _Exit.values) {
      testWidgets('ends open on ${how.name}', (tester) async {
        await boot(tester, views: true, keepsDrawerOpen: true);
        await next(tester);
        await next(tester);
        expect(c.isDrawerOpen.value, isFalse);
        switch (how) {
          case _Exit.finish:
            for (var i = 0; i < 4; i++) {
              await next(tester);
            }
            await tester.tap(find.text(TourTexts.done));
          case _Exit.skip:
            await tester.tap(find.text(TourTexts.skip));
          case _Exit.cancel:
            service.cancel();
          case _Exit.leaveTab:
            c.setActive(false);
        }
        await pumpTour(tester);
        await pumpTour(tester);
        expect(service.isActive.value, isFalse);
        expect(
          c.isDrawerOpen.value,
          how != _Exit.leaveTab,
          reason: 'a left tab shuts its drawer, the others put it back',
        );
        expect(c.table.value, isNull);
        expect(c.current.value, isNull);
        expect(c.selectedViewId.value, isNull);
        expect(c.isTourSampleShown, isFalse);
        expect(tour.demo.isDriving, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a real view open, drawer shut: ends shut, view kept', (
      tester,
    ) async {
      await boot(tester, views: true, opens: true);
      expect(service.isActive.value, isTrue);
      final real = c.table.value;
      final current = c.current.value;
      final selected = c.selectedViewId.value;
      await next(tester);
      await next(tester);
      expect(c.isDrawerOpen.value, isFalse);
      await tester.tap(find.text(TourTexts.skip));
      await pumpTour(tester);
      expect(service.isActive.value, isFalse);
      expect(c.isDrawerOpen.value, isFalse);
      expect(c.table.value, same(real));
      expect(c.current.value, same(current));
      expect(c.selectedViewId.value, selected);
    });

    for (final startsOpen in [true, false]) {
      testWidgets('going back and ending put the drawer as it was '
          '(${startsOpen ? 'open' : 'shut'} at the start)', (tester) async {
        await tester.pumpWidget(const SizedBox());
        Future<void> run(Future<void> f) async {
          var isDone = false;
          unawaited(f.then((_) => isDone = true));
          for (var i = 0; i < 20 && !isDone; i++) {
            await tester.pump();
          }
          expect(isDone, isTrue);
        }

        var drawer = startsOpen;
        var picked = false;
        final ports = SvTourPorts(
          seed: () => false,
          restore: () {},
          openDrawer: () => drawer = true,
          closeDrawer: () => drawer = false,
          pick: () => picked = true,
          unpick: () => picked = false,
          expandFirst: () {},
          collapseFirst: () {},
          openFilter: () {},
          closeFilter: () {},
        );
        final steps = tour.steps(
          ports,
          isSample: true,
          isDrawerOpen: startsOpen,
        );
        final runner = TourRunner(isReduced: true);
        await run(runner.enter(null, steps[0]));
        expect(drawer, isTrue, reason: 'step 1 shows the drawer');
        await run(runner.enter(steps[0], steps[1]));
        expect(drawer, isFalse);
        expect(picked, isTrue);
        await run(runner.enter(steps[1], steps[0]));
        expect(drawer, isTrue, reason: 'back to step 1 reopens it');
        expect(picked, isFalse);
        await run(runner.enter(steps[0], steps[1]));
        runner.restore();
        expect(drawer, startsOpen);
        expect(picked, isFalse);
      });
    }
  });

  group('real data wins', () {
    testWidgets('views and an open view with records: all of it is real', (
      tester,
    ) async {
      await boot(tester, views: true, opens: true);
      expect(service.isActive.value, isTrue);
      final real = c.table.value;
      final current = c.current.value;
      final asked = rig.socket.calls.length;
      expect(real!.rows, isNotEmpty);
      expect(find.text(TourTexts.sampleTag), findsNothing);
      expect(c.isDrawerOpen.value, isTrue);
      expect(find.text(TourTexts.svSampleViewCaption), findsNothing);
      expect(find.text('Tickets'), findsWidgets);

      await next(tester);
      expect(c.table.value, same(real));
      expect(c.isTourSampleShown, isFalse);
      expect(find.byType(SmartViewCard), findsNWidgets(2));
      expect(find.text(TourTexts.sampleTag), findsNothing);
      for (var i = 0; i < 5; i++) {
        await next(tester);
      }
      expect(c.expanded, contains(c.shownRows.first.id));
      await tester.tap(find.text(TourTexts.done));
      await pumpTour(tester);
      await pumpTour(tester);
      expectClean();
      expect(c.table.value, same(real), reason: 'the user\'s own view');
      expect(c.current.value, same(current));
      expect(c.expanded, isEmpty);
      expect(rig.socket.calls.length, asked);
    });

    testWidgets('own views but none open: real list, sample records', (
      tester,
    ) async {
      await boot(tester, views: true);
      expect(service.isActive.value, isTrue);
      final names = c.sources.map((s) => s.name).toList();
      expect(names, isNotEmpty);
      expect(find.text(TourTexts.svSampleViewCaption), findsNothing);
      await next(tester);
      expect(c.isTourSampleShown, isTrue);
      expect(c.sources.map((s) => s.name).toList(), names);
      service.cancel();
      await pumpTour(tester);
      expectClean();
      expect(c.table.value, isNull);
      expect(c.current.value, isNull);
    });

    testWidgets('a real view arriving mid-tour replaces the sample view', (
      tester,
    ) async {
      await boot(tester);
      expect(find.text(TourTexts.svSampleViewCaption), findsOneWidget);
      rig.socket.answers[SvCmd.sources] = captured('004');
      unawaited(c.loadList(isForced: true));
      await pumpTour(tester);
      await pumpTour(tester);
      expect(c.sources, isNotEmpty);
      expect(find.text(TourTexts.svSampleViewCaption), findsNothing);
      expect(tester.takeException(), isNull);
      service.cancel();
      await pumpTour(tester);
      expectClean();
    });
  });

  group('small screens', () {
    testWidgets('320 px wide, text x1.5: the whole tour, no exception', (
      tester,
    ) async {
      await boot(tester, width: 320, scale: 1.5);
      for (var i = 0; i < 6; i++) {
        expect(tester.takeException(), isNull, reason: 'step $i');
        await next(tester);
      }
      await tester.tap(find.text(TourTexts.done));
      await pumpTour(tester);
      await pumpTour(tester);
      expectClean();
      expect(tester.takeException(), isNull);
    });
  });

  test('the sample is plain memory and ends cleanly', () {
    final d = SvTourDemo();
    d.begin(isList: true, isRecords: true, now: 1000000);
    expect(d.isDriving, isTrue);
    expect(d.table!.rows.every((r) => r.id < 0), isTrue);
    expect(d.isSampleTable(d.table), isTrue);
    d.end();
    d.end();
    expect(d.table, isNull);
    expect(d.isDriving, isFalse);
  });
}

SvTourPorts _ports() => SvTourPorts(
  seed: () => false,
  restore: () {},
  openDrawer: () {},
  closeDrawer: () {},
  pick: () {},
  unpick: () {},
  expandFirst: () {},
  collapseFirst: () {},
  openFilter: () {},
  closeFilter: () {},
);
