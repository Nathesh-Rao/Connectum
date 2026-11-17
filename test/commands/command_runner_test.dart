import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/data/commands/command_reply.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/features/commands/command_runner.dart';
import 'package:connectum/features/conversation/models/command_prompt.dart';
import 'package:connectum/features/forms/models/form_launch.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Commands extends Fake implements CommandRepository {
  HashResult next = const HashResult(
    HashKind.form,
    '',
    '',
    '',
    '',
    [],
    [],
    'x',
  );
  final lines = <String>[];

  @override
  CommandSuggester createSuggester() =>
      CommandSuggester((_, _, _) async => null);

  @override
  Future<HashResult> run(
    String line, {
    String? activeConvId,
    bool isConfirmed = false,
  }) async {
    lines.add(line);
    return next;
  }
}

class _Submissions extends Fake implements SubmissionRepository {
  StructureOpen answer = const StructureOpen('leave_request', 'user', 'Leave');
  final asked = <String>[];

  @override
  Future<StructureOpen> openStructure(String typed) async {
    asked.add(typed);
    return answer;
  }
}

class _Shell extends Fake implements HomeShellController {
  final opened = <String>[];

  @override
  void openSubmissionsOf(String formName) => opened.add(formName);
}

HashResult _r(HashKind kind, String target) =>
    HashResult(kind, '', '', '', '', const [], const [], target);

void main() {
  late _Commands commands;
  late _Submissions submissions;
  late _Shell shell;
  late CommandRunner runner;
  FormLaunch? launched;

  Future<void> boot(
    WidgetTester tester, {
    String? chat,
  }) async {
    launched = null;
    commands = _Commands();
    submissions = _Submissions();
    shell = _Shell();
    runner = CommandRunner(
      commands,
      CommandPrompt(commands),
      submissions: submissions,
      shell: shell,
      chatConvId: chat,
      chatTitle: () => 'Ana Lopez',
    );
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Text('workspace')),
        getPages: [
          GetPage(
            name: AppRoutes.form,
            page: () {
              launched = Get.arguments as FormLaunch?;
              return const Scaffold(body: Text('form'));
            },
          ),
        ],
      ),
    );
  }

  testWidgets(
    '#tstruct-add opens the form for the structure the server named',
    (tester) async {
      await boot(tester);
      commands.next = _r(HashKind.form, 'Leave');
      late bool cleared;
      await tester.runAsync(
        () async => cleared = await runner.run('#tstruct-add Leave'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(cleared, isTrue);
      expect(submissions.asked, ['Leave']);
      expect(find.text('form'), findsOneWidget);
      expect(launched?.name, 'leave_request');
      expect(launched?.scope, 'user');
      expect(launched?.convId, isNull);
      expect(launched?.mode, FormMode.create);
    },
  );

  testWidgets('#tstruct shows My Submissions of that form', (tester) async {
    await boot(tester);
    commands.next = _r(HashKind.records, 'Leave');
    late bool cleared;
    await tester.runAsync(
      () async => cleared = await runner.run('#tstruct Leave'),
    );
    expect(cleared, isTrue);
    expect(shell.opened, ['leave_request']);
    expect(find.text('form'), findsNothing);
  });

  testWidgets('a structure that is gone keeps the text and opens nothing', (
    tester,
  ) async {
    await boot(tester);
    commands.next = _r(HashKind.form, 'Nope');
    submissions.answer = const StructureOpen.failed(
      'No such structure, or it is not available to you.',
      code: 'not_found',
    );
    late bool cleared;
    await tester.runAsync(
      () async => cleared = await runner.run('#tstruct-add Nope'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(cleared, isFalse);
    expect(find.text('form'), findsNothing);
    expect(shell.opened, isEmpty);
  });

  testWidgets('offline with nothing kept and rate_limited open nothing', (
    tester,
  ) async {
    await boot(tester);
    commands.next = _r(HashKind.form, 'Leave');
    for (final answer in const [
      StructureOpen.failed('', isOffline: true),
      StructureOpen.failed('slow down', code: 'rate_limited'),
    ]) {
      submissions.answer = answer;
      late bool cleared;
      await tester.runAsync(
        () async => cleared = await runner.run('#tstruct-add Leave'),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(cleared, isFalse);
    }
    expect(find.text('form'), findsNothing);
  });

  testWidgets('another command still says coming soon and opens nothing', (
    tester,
  ) async {
    await boot(tester);
    commands.next = const HashResult(
      HashKind.soon,
      CommandRepository.comingSoon,
    );
    late bool cleared;
    await tester.runAsync(() async => cleared = await runner.run('#find ana'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(cleared, isTrue);
    expect(submissions.asked, isEmpty);
    expect(find.text('form'), findsNothing);
  });

  Future<FormLaunch?> openFrom(
    WidgetTester tester, {
    String? chat,
  }) async {
    await boot(tester, chat: chat);
    commands.next = _r(HashKind.form, 'Leave');
    await tester.runAsync(() => runner.run('#tstruct-add Leave'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return launched;
  }

  testWidgets('from a direct chat the box is offered, unticked', (
    tester,
  ) async {
    final l = await openFrom(tester, chat: 'dm:ana');
    expect(l?.hasPostChoice, isTrue);
    expect(l?.convId, 'dm:ana');
    expect(l?.postChoiceTitle, 'Ana Lopez');
    expect(l?.isPostedByDefault, isFalse);
  });

  testWidgets('from a group the box is offered, unticked', (tester) async {
    final l = await openFrom(tester, chat: 'group:sales');
    expect(l?.hasPostChoice, isTrue);
    expect(l?.convId, 'group:sales');
    expect(l?.isPostedByDefault, isFalse);
  });

  testWidgets("in a person's care thread the box starts ticked", (
    tester,
  ) async {
    final l = await openFrom(tester, chat: 'group:care-ana.lopez');
    expect(l?.hasPostChoice, isTrue);
    expect(l?.isPostedByDefault, isTrue);
  });

  for (final chat in const [null, 'global', 'host:hr']) {
    testWidgets('no box in the Work Space, global room or team ($chat)', (
      tester,
    ) async {
      final l = await openFrom(tester, chat: chat);
      expect(l?.name, 'leave_request');
      expect(l?.hasPostChoice, isFalse);
      expect(l?.convId, isNull);
    });
  }

  for (final chat in const ['dm:ana', 'group:sales']) {
    testWidgets('an encrypted chat gets the box too, as on the web ($chat)', (
      tester,
    ) async {
      final l = await openFrom(tester, chat: chat);
      expect(l?.hasPostChoice, isTrue);
      expect(l?.convId, chat);
      expect(l?.isPostedByDefault, isFalse);
    });
  }
}
