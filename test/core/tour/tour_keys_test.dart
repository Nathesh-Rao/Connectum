import 'dart:async';

import 'package:connectum/core/tour/tour_service.dart';
import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/notifications/local_notification_service.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/smart_view/sv_prefs.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_tour.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:connectum/features/notifications/notifications_controller.dart';
import 'package:connectum/features/notifications/notifications_tour.dart';
import 'package:connectum/features/notifications/notifications_view.dart';
import 'package:connectum/features/smart_view/models/smart_view_entry.dart';
import 'package:connectum/features/smart_view/smart_view_binding.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../inbox/inbox_screen_support.dart';
import '../../smart_view/sv_support.dart';
import '../../support/fake_socket.dart';
import 'tour_test_support.dart';

class _Router extends Fake implements NotificationRouter {}

class _Notifications extends Fake implements LocalNotificationService {
  @override
  final isEnabled = true.obs;

  @override
  final wasAsked = false.obs;

  @override
  final shouldNotifyGroups = true.obs;
}

class _Connectivity extends Fake implements ConnectivityService {
  @override
  final state = AppConnectivity.online.obs;
}

class _Conversations extends Fake implements ConversationRepository {
  @override
  final conversations = <Never>[].obs;
}

class _Submissions extends GetxService implements SubmissionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SvConnectivity extends ConnectivityService {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.value = AppConnectivity.online;
  }

  @override
  void attachSocket(Rx<SocketState> socketState) {}
}

/// A service whose tours never start: only the keys are under test.
TourService _service() => TourService(
  userId: () => 'u1',
  store: memoryStore(),
  blockers: [() => true],
  blockerNames: ['test'],
);

Future<void> _pumpFor(WidgetTester tester, [int ms = 400]) async {
  for (var t = 0; t < ms; t += 40) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Inbox', () {
    testWidgets('loading, data and empty switch without a key clash', (
      t,
    ) async {
      final rig = InboxRig(tour: InboxTour(service: _service()));
      final gate = Completer<void>();
      rig.routes['records.query'] = (a) async {
        if (a['facets'] == true) {
          return {
            'submissions': <Object>[],
            'structures': <String, Object>{},
            'total': 0,
            'formCounts': <String, Object>{},
            'people': <String, Object>{},
          };
        }
        await gate.future;
        return queryReply([for (var i = 3; i > 0; i--) record(i)]);
      };
      Get.put(rig.controller);
      addTearDown(Get.reset);
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(const MaterialApp(home: InboxView()));
      await _pumpFor(t);
      expect(rig.controller.viewState.value, AppViewState.loading);
      expect(t.takeException(), isNull);

      gate.complete();
      await _pumpFor(t, 600);
      expect(rig.controller.viewState.value, AppViewState.content);
      expect(t.takeException(), isNull);
      expect(find.byKey(rig.controller.tour!.cardKey), findsOneWidget);

      for (final s in [
        AppViewState.empty,
        AppViewState.loading,
        AppViewState.content,
        AppViewState.empty,
      ]) {
        rig.controller.viewState.value = s;
        await t.pump(const Duration(milliseconds: 60));
        expect(t.takeException(), isNull, reason: s.name);
        await _pumpFor(t, 400);
        expect(t.takeException(), isNull, reason: '${s.name} settled');
      }
      await t.pumpWidget(const SizedBox());
      rig.dispose();
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('Smart View', () {
    testWidgets('loading, rows, empty and a view switch hold each key once', (
      t,
    ) async {
      Get.reset();
      final rig = SvRig();
      rig.socket.answers[SvCmd.sources] = captured('004');
      rig.socket.answers['record.actions'] = captured('030');
      Get.put<SmartViewRepository>(rig.repo);
      Get.put<TicketRepository>(rig.tickets);
      Get.put<SubmissionRepository>(_Submissions());
      Get.put<FormFileRepository>(FakeFiles());
      Get.put<ConnectivityService>(_SvConnectivity());
      Get.put<TourService>(_service());
      addTearDown(() {
        rig.tickets.onClose();
        rig.repo.onClose();
        Get.reset();
      });
      rig.socket.answers['submissions.list'] = listPager([
        ownRow(2, ts: 1794833216651),
        ownRow(1, ts: 1794833216000),
      ]);
      rig.socket.answers['records.mine'] = minePager({
        'with': <Map<String, dynamic>>[],
      }, pageSize: 50);
      t.view.physicalSize = const Size(390 * 2, 844 * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.resetPhysicalSize);
      SmartViewBinding().dependencies();
      await t.pumpWidget(const GetMaterialApp(home: SmartViewView()));
      await t.pump();
      final c = Get.find<SmartViewController>();
      unawaited(c.enter(SmartViewEntry.named('tickets')));
      await _pumpFor(t, 200);
      expect(t.takeException(), isNull, reason: 'loading');
      await _pumpFor(t, 800);
      expect(t.takeException(), isNull, reason: 'rows');
      expect(find.byKey(c.tour!.cardKey), findsOneWidget);

      c.selectedViewId.value = 'other';
      await t.pump(const Duration(milliseconds: 60));
      expect(t.takeException(), isNull, reason: 'view switch');
      c.selectedViewId.value = null;
      await t.pump(const Duration(milliseconds: 60));
      expect(t.takeException(), isNull, reason: 'view switch back');

      c.setMode(SvViewMode.table);
      await t.pump(const Duration(milliseconds: 60));
      c.setMode(SvViewMode.cards);
      await t.pump(const Duration(milliseconds: 60));
      expect(t.takeException(), isNull, reason: 'mode switch');

      c.setQuery(c.query.value.copyWith(search: 'no such row'));
      await _pumpFor(t, 600);
      expect(t.takeException(), isNull, reason: 'no match');
      c.setQuery(c.query.value.copyWith(search: ''));
      await _pumpFor(t, 600);
      expect(t.takeException(), isNull, reason: 'rows again');
    });
  });

  group('Notifications', () {
    testWidgets('loading, items and empty hold the body key once', (t) async {
      final socket = FakeSocket()..goOnline();
      final feed = FeedRepository(socket, FakeStore(), FakeE2e())..onInit();
      addTearDown(feed.onClose);
      Map<String, dynamic> counts(int n) => {
        'high': n,
        'medium': 0,
        'low': 0,
        'resolved': 0,
        'unread': n,
        'total': n,
      };
      Map<String, dynamic> page(int n) => {
        'counts': counts(n),
        'hasMore': false,
        'notifications': [
          for (var i = 0; i < n; i++)
            {
              'id': 'n$i',
              'ts': 100 + i,
              'read': false,
              'priority': 'high',
              'resolved': false,
              'title': 'T$i',
              'message': 'M$i',
            },
        ],
      };
      socket.answers['feed.summary'] = counts(3);
      socket.answers['feed.list'] = page(3);
      final c = NotificationsController(
        feed: feed,
        router: _Router(),
        notifications: _Notifications(),
        connectivity: _Connectivity(),
        conversations: _Conversations(),
        tour: NotificationsTour(service: _service()),
      );
      Get.put(c);
      addTearDown(Get.reset);
      t.view.physicalSize = const Size(390, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(const GetMaterialApp(home: NotificationsView()));
      await _pumpFor(t, 100);
      expect(t.takeException(), isNull, reason: 'loading');
      await _pumpFor(t, 600);
      expect(t.takeException(), isNull, reason: 'items');

      socket.answers['feed.summary'] = counts(0);
      socket.answers['feed.list'] = page(0);
      await feed.refresh();
      await _pumpFor(t, 600);
      expect(t.takeException(), isNull, reason: 'empty');

      socket.answers['feed.summary'] = counts(2);
      socket.answers['feed.list'] = page(2);
      await feed.refresh();
      await _pumpFor(t, 600);
      expect(t.takeException(), isNull, reason: 'items again');
      expect(find.byKey(c.tour!.bodyKey), findsOneWidget);
    });
  });
}
