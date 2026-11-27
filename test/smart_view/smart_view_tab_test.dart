import 'dart:async';

import 'package:connectum/core/debug/seed_smart_view.dart';
import 'package:connectum/core/debug/seed_tickets.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/app_text_field.dart';
import 'package:connectum/data/e2e/e2e_models.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/notifications/local_notification_service.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/e2e_repository.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:connectum/features/security/security_controller.dart';
import 'package:connectum/features/smart_view/models/smart_view_entry.dart';
import 'package:connectum/features/smart_view/smart_view_binding.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:connectum/core/widgets/app_speed_dial.dart';
import 'package:connectum/features/smart_view/widgets/sv_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

const _rows = 'submissions.list';

class _Conversations extends Fake implements ConversationRepository {
  @override
  final conversations = <Conversation>[].obs;
}

class _E2e extends Fake implements E2eRepository {
  @override
  final phase = E2eSetupPhase.idle.obs;
  @override
  final isLate = false.obs;
  @override
  final lateHint = ''.obs;
  @override
  final notice = ''.obs;
  @override
  Stream<E2eNotice> get notices => const Stream.empty();
}

class _Security extends Fake implements SecurityController {
  @override
  final E2eRepository e2e = _E2e();
}

class _Router extends Fake implements NotificationRouter {
  @override
  void Function(HomeTab tab)? selectTab;

  @override
  void Function()? openApprovals;

  @override
  void Function(int id)? openRecord;

  @override
  void Function()? openInboxList;

  @override
  void markHomeGone() {}

  @override
  void markHomeReady() {}
}

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

class _Pushes extends NavigatorObserver {
  int count = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

Future<void> pumpFor(WidgetTester tester, [int ms = 700]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SvRig rig;
  late SmartViewController smart;
  late HomeShellController shell;
  late _Pushes pushes;

  Future<void> boot(WidgetTester tester) async {
    Get.reset();
    rig = SvRig();
    rig.socket.answers[SvCmd.sources] = captured('004');
    rig.socket.answers[_rows] = listPager([
      ownRow(2, values: {'title': 'Second'}),
      ownRow(1, values: {'title': 'First'}),
    ]);
    rig.socket.answers['records.mine'] = {
      'submissions': <Object>[],
      'hasMore': false,
    };
    rig.socket.answers['record.actions'] = captured('030');
    Get.put<SmartViewRepository>(rig.repo);
    Get.put<TicketRepository>(rig.tickets);
    Get.put<SubmissionRepository>(_Submissions());
    Get.put<FormFileRepository>(FakeFiles());
    Get.put<ConnectivityService>(_Connectivity());
    SmartViewBinding().dependencies();
    smart = Get.find<SmartViewController>();
    shell = HomeShellController(
      conversations: _Conversations(),
      security: _Security(),
      links: _Links(),
      notifications: _Notifications(),
      notificationRouter: _Router(),
      smartView: smart,
    )..onInit();
    pushes = _Pushes();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() {
      rig.tickets.onClose();
      rig.repo.onClose();
      Get.reset();
    });
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        initialRoute: AppRoutes.chats,
        navigatorObservers: [pushes],
        getPages: [
          GetPage(name: AppRoutes.chats, page: () => const SmartViewView()),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('#view: the Smart view tab is selected, the drawer open', (
    tester,
  ) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.drawer());
    await pumpFor(tester);
    expect(shell.tab.value, HomeTab.smartView);
    expect(smart.isDrawerOpen.value, isTrue);
    expect(smart.isActive.value, isTrue);
    expect(smart.current.value, isNull);
    expect(find.byKey(const ValueKey('sv-drawer-tickets')), findsOneWidget);
    expect(find.byKey(const ValueKey('sv-drawer-requests')), findsOneWidget);
  });

  testWidgets(
    '#view <name>: tab selected, drawer closed, that view asked for',
    (tester) async {
      await boot(tester);
      shell.openSmartView(const SmartViewEntry.named('tickets'));
      await pumpFor(tester, 1500);
      expect(shell.tab.value, HomeTab.smartView);
      expect(smart.isDrawerOpen.value, isFalse);
      expect(smart.current.value?.name, 'tickets');
      expect(rig.count(_rows), greaterThan(0));
      expect(
        rig.socket.calls.firstWhere((c) => c.action == _rows).args['tstruct'],
        'tickets',
      );
      expect(find.text('Second'), findsOneWidget);
    },
  );

  testWidgets('a second #view on the tab updates it and pushes nothing', (
    tester,
  ) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.named('tickets'));
    await pumpFor(tester, 1500);
    final before = pushes.count;
    shell.openSmartView(const SmartViewEntry.drawer());
    await pumpFor(tester);
    expect(smart.isDrawerOpen.value, isTrue);
    shell.openSmartView(const SmartViewEntry.named('requests'));
    await pumpFor(tester, 1500);
    expect(smart.isDrawerOpen.value, isFalse);
    expect(smart.current.value?.name, 'requests');
    expect(pushes.count, before);
  });

  testWidgets('the tab alone with no view open: the list, drawer open', (
    tester,
  ) async {
    await boot(tester);
    shell.select(HomeTab.smartView);
    await pumpFor(tester, 1500);
    expect(smart.current.value, isNull);
    expect(smart.isDrawerOpen.value, isTrue);
    expect(find.byKey(const ValueKey('sv-drawer-overview')), findsNothing);
    expect(find.byKey(const ValueKey('sv-drawer-tickets')), findsOneWidget);
    expect(find.byType(SvControls), findsNothing);
  });

  testWidgets('the tab alone with a view open: it resumes, drawer closed', (
    tester,
  ) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.named('tickets'));
    await pumpFor(tester, 1500);
    expect(smart.current.value?.name, 'tickets');
    shell.select(HomeTab.chats);
    shell.select(HomeTab.smartView);
    await pumpFor(tester, 1500);
    expect(smart.isDrawerOpen.value, isFalse);
    expect(smart.current.value?.name, 'tickets');
    expect(find.byType(SvControls), findsOneWidget);
    expect(find.byType(AppSpeedDial), findsOneWidget);
  });

  testWidgets('#view with a view open: the drawer opens, the view stays', (
    tester,
  ) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.named('tickets'));
    await pumpFor(tester, 1500);
    shell.openSmartView(const SmartViewEntry.drawer());
    await pumpFor(tester, 500);
    expect(smart.isDrawerOpen.value, isTrue);
    expect(smart.current.value?.name, 'tickets');
  });

  testWidgets('re-tapping the tab changes nothing', (tester) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.named('tickets'));
    await pumpFor(tester, 1500);
    shell.select(HomeTab.smartView);
    await pumpFor(tester, 500);
    expect(smart.current.value?.name, 'tickets');
    expect(smart.isDrawerOpen.value, isFalse);
  });

  testWidgets('back: drawer open closes it first, then the screen is left', (
    tester,
  ) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.named('tickets'));
    await pumpFor(tester, 1500);
    expect(smart.canLeave, isTrue);
    smart.openDrawer();
    await pumpFor(tester);
    expect(smart.canLeave, isFalse);
    await tester.binding.handlePopRoute();
    await pumpFor(tester);
    expect(smart.isDrawerOpen.value, isFalse);
    expect(smart.current.value?.name, 'tickets');
    expect(smart.canLeave, isTrue);
  });

  testWidgets('back closes the drawer first, then leaves it to the route', (
    tester,
  ) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.drawer());
    await pumpFor(tester);
    expect(smart.isDrawerOpen.value, isTrue);
    await tester.binding.handlePopRoute();
    await pumpFor(tester);
    expect(smart.isDrawerOpen.value, isFalse);
  });

  testWidgets('leaving the tab closes the drawer', (tester) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.drawer());
    await pumpFor(tester);
    shell.select(HomeTab.chats);
    await pumpFor(tester);
    expect(smart.isDrawerOpen.value, isFalse);
    expect(smart.isActive.value, isFalse);
  });

  group('the drawer', () {
    testWidgets('Find filters the list, any case, locally', (tester) async {
      await boot(tester);
      shell.openSmartView(const SmartViewEntry.drawer());
      await pumpFor(tester);
      Finder row(String n) => find.byKey(ValueKey('sv-drawer-$n'));
      expect(row('tickets'), findsOneWidget);
      expect(row('requests'), findsOneWidget);
      final calls = rig.socket.calls.length;
      await tester.enterText(find.byType(TextField), 'TICK');
      await pumpFor(tester, 100);
      expect(row('tickets'), findsOneWidget);
      expect(row('requests'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzzz');
      await pumpFor(tester, 100);
      expect(find.text('Nothing matches.'), findsOneWidget);
      expect(rig.socket.calls.length, calls);
    });

    testWidgets('the open view is the violet pill; selecting closes', (
      tester,
    ) async {
      await boot(tester);
      shell.openSmartView(const SmartViewEntry.named('tickets'));
      await pumpFor(tester, 1500);
      smart.openDrawer();
      await pumpFor(tester);
      Color? fillOf(String name) {
        final box = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(ValueKey('sv-drawer-$name')),
                matching: find.byType(Container),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      expect(fillOf('tickets'), AppColors.violetTint);
      expect(fillOf('requests'), Colors.transparent);
      await tester.tap(find.byKey(const ValueKey('sv-drawer-requests')));
      await pumpFor(tester, 1500);
      expect(smart.isDrawerOpen.value, isFalse);
      expect(smart.current.value?.name, 'requests');
    });

    testWidgets('Find and the rows share the same edges; labels sit under '
        'the search icon', (tester) async {
      await boot(tester);
      shell.openSmartView(const SmartViewEntry.named('tickets'));
      await pumpFor(tester, 1500);
      smart.openDrawer();
      await pumpFor(tester);
      final find0 = tester.getRect(find.byType(AppTextField));
      final pill = tester.getRect(
        find.byKey(const ValueKey('sv-drawer-tickets')),
      );
      expect(pill.left, find0.left);
      expect(pill.right, find0.right);
      final label = tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const ValueKey('sv-drawer-tickets')),
              matching: find.text('Tickets'),
            ),
          )
          .dx;
      final icon = tester
          .getTopLeft(
            find.descendant(
              of: find.byType(AppTextField),
              matching: find.byIcon(Icons.search),
            ),
          )
          .dx;
      expect(label, closeTo(icon, 1));
      expect(tester.getTopLeft(find.text('Smart view')).dx, find0.left);
      expect(tester.getTopLeft(find.text('STRUCTURES')).dx, find0.left);
    });

    testWidgets('golden: the open drawer, the open view as a violet pill', (
      tester,
    ) async {
      await boot(tester);
      shell.openSmartView(const SmartViewEntry.named('tickets'));
      await pumpFor(tester, 1500);
      smart.openDrawer();
      await pumpFor(tester);
      await expectLater(
        find.byType(GetMaterialApp),
        matchesGoldenFile('goldens/sv_drawer_open.png'),
      );
    });

    testWidgets('no views: a calm empty state', (tester) async {
      await boot(tester);
      rig.socket.answers[SvCmd.sources] = {'forms': <Object>[]};
      shell.openSmartView(const SmartViewEntry.drawer());
      await pumpFor(tester);
      expect(find.text('No smart views yet'), findsWidgets);
    });

    testWidgets('DEMO: the drawer lists the demo structures', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        await SeedTickets.start();
        await SeedSmartView.start(isLive: false);
      });
      addTearDown(() {
        SeedSmartView.stop();
        SeedTickets.stop();
      });
      shell.openSmartView(const SmartViewEntry.drawer());
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('sv-drawer-leave')), findsOneWidget);
      expect(find.byKey(const ValueKey('sv-drawer-expense')), findsOneWidget);
    });
  });
}

class _Links extends Fake implements DeepLinkService {
  @override
  Future<void> resume() async {}
}

class _Notifications extends Fake implements LocalNotificationService {
  @override
  bool get shouldExplain => false;
}
