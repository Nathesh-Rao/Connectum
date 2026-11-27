import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/data/commands/command_reply.dart';
import 'package:connectum/data/e2e/e2e_models.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/notifications/local_notification_service.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/e2e_repository.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/commands/command_runner.dart';
import 'package:connectum/features/conversation/models/command_prompt.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:connectum/features/security/security_controller.dart';
import 'package:connectum/features/smart_view/models/smart_view_entry.dart';
import 'package:connectum/features/smart_view/smart_view_binding.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../smart_view/sv_support.dart';
import '../support/fake_socket.dart';

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

class _Links extends Fake implements DeepLinkService {
  @override
  Future<void> resume() async {}
}

class _Notifications extends Fake implements LocalNotificationService {
  @override
  bool get shouldExplain => false;
}

class _Commands extends Fake implements CommandRepository {
  @override
  CommandSuggester createSuggester() =>
      CommandSuggester((_, _, _) async => null);

  @override
  Future<HashResult> run(
    String line, {
    String? activeConvId,
    bool isConfirmed = false,
  }) async => HashResult(
    HashKind.screen,
    '',
    '',
    '',
    '',
    const [],
    const [],
    line.trim().substring(1),
  );
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
  late CommandRunner runner;
  late _Router router;

  Future<void> boot(WidgetTester tester) async {
    Get.reset();
    rig = SvRig();
    rig.socket.answers[SvCmd.sources] = captured('004');
    rig.socket.answers['submissions.list'] = listPager([
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
      notificationRouter: router = _Router(),
      smartView: smart,
    )..onInit();
    final commands = _Commands();
    runner = CommandRunner(commands, CommandPrompt(commands), shell: shell);
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
        initialRoute: AppRoutes.chats,
        getPages: [
          GetPage(
            name: AppRoutes.chats,
            page: () => const Scaffold(body: Text('home')),
          ),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('#inbox selects the Inbox tab', (tester) async {
    await boot(tester);
    expect(shell.tab.value, HomeTab.chats);
    await runner.run('#inbox');
    await pumpFor(tester);
    expect(shell.tab.value, HomeTab.inbox);
    expect(shell.isBuilt[HomeTab.inbox.index], isTrue);
  });

  testWidgets(
    'openInbox(approvals: true) shows the Inbox and asks for the pane',
    (tester) async {
      await boot(tester);
      expect(shell.approvalsRequest.value, isFalse);
      shell.openInbox(approvals: true);
      await pumpFor(tester);
      expect(shell.tab.value, HomeTab.inbox);
      expect(shell.approvalsRequest.value, isTrue);
    },
  );

  testWidgets('plain openInbox (#inbox) does not ask for the pane', (
    tester,
  ) async {
    await boot(tester);
    shell.openInbox();
    await pumpFor(tester);
    expect(shell.tab.value, HomeTab.inbox);
    expect(shell.approvalsRequest.value, isFalse);
  });

  testWidgets('a notification tap (the router hook) opens the Inbox pane', (
    tester,
  ) async {
    await boot(tester);
    expect(router.openApprovals, isNotNull);
    router.openApprovals!();
    await pumpFor(tester);
    expect(shell.tab.value, HomeTab.inbox);
    expect(shell.approvalsRequest.value, isTrue);
  });

  testWidgets('#view still selects Smart view; each tab keeps its state', (
    tester,
  ) async {
    await boot(tester);
    shell.openSmartView(const SmartViewEntry.named('tickets'));
    await pumpFor(tester, 1500);
    expect(shell.tab.value, HomeTab.smartView);
    expect(smart.current.value?.name, 'tickets');

    await runner.run('#inbox');
    await pumpFor(tester);
    expect(shell.tab.value, HomeTab.inbox);
    expect(smart.current.value?.name, 'tickets');
    expect(smart.isActive.value, isFalse);

    shell.openSmartView(const SmartViewEntry.named('tickets'));
    await pumpFor(tester, 1500);
    expect(shell.tab.value, HomeTab.smartView);
    expect(smart.isActive.value, isTrue);
  });

  testWidgets('without a home, #inbox falls back to the first route', (
    tester,
  ) async {
    await boot(tester);
    final commands = _Commands();
    final bare = CommandRunner(commands, CommandPrompt(commands));
    await bare.run('#inbox');
    await pumpFor(tester, 200);
    expect(shell.tab.value, HomeTab.chats);
  });
}
