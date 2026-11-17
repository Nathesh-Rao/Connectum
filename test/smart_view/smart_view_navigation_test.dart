import 'dart:async';

import 'package:connectum/core/debug/seed_commands.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/commands/command_runner.dart';
import 'package:connectum/features/conversation/models/command_prompt.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/smart_view/models/smart_view_entry.dart';
import 'package:connectum/features/smart_view/smart_view_binding.dart';
import 'package:connectum/features/smart_view/smart_view_controller.dart';
import 'package:connectum/features/smart_view/smart_view_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'sv_support.dart';

class _Socket extends FakeSocket {
  final _bus = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get events => _bus.stream;

  @override
  bool isCurrent(Map<String, dynamic> event) => true;

  @override
  Future<bool> sendCommand(String line) async {
    if (!isOnline) return false;
    if (line == '/cmds') {
      scheduleMicrotask(() => _bus.add(SeedCommands.catalogFrame()));
    }
    return true;
  }
}

class _Store extends FakeStore {
  @override
  Future<String?> readValue(String key) async => null;

  @override
  Future<void> writeValue(String key, String value) async {}
}

class _Messages extends Fake implements MessageRepository {}

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

Future<void> pumpFor(WidgetTester tester, [int ms = 600]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The whole way a person goes, in a real [GetMaterialApp]: type `#view` in a
/// message box, pick a structure, read its cards, open a record, come back.
/// The message box is a bare field that runs [CommandRunner] the way the real
/// composers do; the commands, the source list, the repository, the screen
/// and the routes are the real ones. A fake socket answers; nothing else.
/// Stands for the home: the Smart view tab is a pushed page, entered the way
/// the home enters it.
class _Shell extends Fake implements HomeShellController {
  @override
  void openSmartView(SmartViewEntry entry) {
    unawaited(Get.toNamed(AppRoutes.smartView));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(Get.find<SmartViewController>().enter(entry)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('composer -> #view -> drawer -> list -> record -> back', (
    tester,
  ) async {
    Get.reset();
    final socket = _Socket()..goOnline();
    final rig = SvRig();
    final commands = CommandRepository(
      socket,
      _Store() as SessionStore,
      FakeConnectivity(),
      _Messages(),
      FakeConversations() as ConversationRepository,
    );
    rig.socket.answers[SvCmd.sources] = captured('004');
    rig.socket.answers['submissions.list'] = listPager([
      ownRow(5, ts: 2000, values: {'title': 'Printer jammed', 'stage': 'Open'}),
      ownRow(
        4,
        ts: 1000,
        values: {'title': 'Invoice mismatch', 'stage': 'Open'},
      ),
    ]);
    rig.socket.answers['records.mine'] = {
      'submissions': <Object>[],
      'hasMore': false,
    };
    rig.socket.answers['record.actions'] = captured('030');
    commands.sourceSuggester = rig.repo.suggestions;
    Get.put<SmartViewRepository>(rig.repo);
    Get.put<TicketRepository>(rig.tickets);
    Get.put<SubmissionRepository>(_Submissions());
    Get.put<FormFileRepository>(FakeFiles());
    Get.put<ConnectivityService>(_Connectivity());
    addTearDown(() {
      rig.tickets.onClose();
      rig.repo.onClose();
      Get.reset();
    });

    final prompt = CommandPrompt(commands);
    final runner = CommandRunner(
      commands,
      prompt,
      smartView: rig.repo,
      shell: _Shell(),
    );
    final text = TextEditingController();
    final kept = <String>[];
    final opened = <String>[];

    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Column(
            children: [
              TextField(key: const ValueKey('box'), controller: text),
              TextButton(
                onPressed: () async {
                  final line = text.text;
                  if (await runner.run(line)) {
                    text.clear();
                  } else {
                    kept.add(line);
                  }
                },
                child: const Text('send'),
              ),
            ],
          ),
        ),
        getPages: [
          GetPage(
            name: AppRoutes.smartView,
            page: () => const SmartViewView(),
            binding: SmartViewBinding(),
          ),
          GetPage(
            name: AppRoutes.ticket,
            page: () {
              opened.add('ticket ${Get.parameters['id']}');
              return Scaffold(
                body: Column(
                  children: [
                    const Text('record screen'),
                    TextButton(onPressed: Get.back, child: const Text('back')),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
    await tester.runAsync(() async {
      await commands.ensureLoaded();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();

    // 1. A wrong name: the text stays, a notice is not a navigation.
    await tester.enterText(find.byKey(const ValueKey('box')), '#view zzz');
    await tester.tap(find.text('send'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await pumpFor(tester, 300);
    expect(text.text, '#view zzz');
    expect(find.text('record screen'), findsNothing);
    expect(find.text('Printer jammed'), findsNothing);

    // 2. No name: the tab opens with the drawer listing every view.
    await tester.enterText(find.byKey(const ValueKey('box')), '#view');
    await tester.tap(find.text('send'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await pumpFor(tester, 2000);
    expect(find.text('Smart view'), findsNWidgets(2));
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(Get.find<SmartViewController>().isDrawerOpen.value, isTrue);
    await tester.tap(find.text('Tickets'));
    await pumpFor(tester, 2000);
    expect(Get.find<SmartViewController>().isDrawerOpen.value, isFalse);

    // 3. The list.
    expect(text.text, '');
    expect(find.text('Printer jammed'), findsOneWidget);
    expect(find.text('Invoice mismatch'), findsOneWidget);
    expect(kept, ['#view zzz']);

    // 4. A record, and back to the list.
    await tester.tap(find.text('Printer jammed'));
    await pumpFor(tester, 800);
    expect(opened, ['ticket 5']);
    expect(find.text('record screen'), findsOneWidget);
    await tester.tap(find.text('back'));
    await pumpFor(tester, 800);
    expect(find.text('Printer jammed'), findsOneWidget);

    // 5. Back out of the list to the message box, then a name opens it at once.
    Get.back<void>();
    await pumpFor(tester, 800);
    expect(find.byKey(const ValueKey('box')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('box')), '#view requests');
    await tester.tap(find.text('send'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await pumpFor(tester, 1200);
    expect(text.text, '');
    expect(find.text('Requests'), findsOneWidget);
    expect(rig.count('ai.enterprise'), 1);
    prompt.dispose();
  });
}
