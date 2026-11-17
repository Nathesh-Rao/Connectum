import 'dart:async';
import 'dart:convert';

import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/form_logic/form_logic_service.dart';
import 'package:connectum/data/models/form_definition.dart';
import 'package:connectum/data/models/form_submission.dart';
import 'package:connectum/data/repositories/form_options_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/forms/form_controller.dart';
import 'package:connectum/features/forms/models/form_launch.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/submission_detail/submission_detail_controller.dart';
import 'package:connectum/features/submissions/submissions_controller.dart';
import 'package:connectum/data/repositories/command_repository.dart';
import 'package:connectum/data/commands/command_reply.dart';
import 'package:connectum/features/commands/command_runner.dart';
import 'package:connectum/features/conversation/models/command_prompt.dart';
import 'package:connectum/features/tickets/saved_record_notice.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

/// A form_definitions table in memory: the smallest stand-in for sqflite
/// that `openStructure` and `reload` touch. Everything else answers empty.
class _Db extends Fake implements AppDatabase {
  final defs = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    if (!sql.contains('FROM form_definitions')) return [];
    return [
      for (final d in defs)
        if (d['org_id'] == args[0] &&
            d['user_id'] == args[1] &&
            (!sql.contains('AND name = ?') || d['name'] == args[2]))
          d,
    ];
  }

  @override
  Future<int> insert(String sql, [List<Object?> args = const []]) async {
    if (sql.contains('INTO form_definitions')) {
      defs
        ..removeWhere(
          (d) =>
              d['org_id'] == args[0] &&
              d['user_id'] == args[1] &&
              d['name'] == args[2],
        )
        ..add({
          'org_id': args[0],
          'user_id': args[1],
          'name': args[2],
          'scope': args[3],
          'caption': args[4],
          'definition_json': args[5],
          'fetched_ts': args[6],
          'rev': args[7],
        });
    }
    return 1;
  }

  @override
  Future<int> update(String sql, [List<Object?> args = const []]) async => 1;
}

class _Options extends Fake implements FormOptionsRepository {
  @override
  Future<void> dropForm(String form, {String? org, String? user}) async {}
}

class _Messages extends Fake implements MessageRepository {}

const _leave = {
  'caption': 'Leave Request',
  'fields': [
    {'name': 'reason', 'caption': 'Reason', 'type': 'text'},
  ],
};

Map<String, dynamic> _opened(Map<String, dynamic> args) {
  final typed = '${args['name']}'.toLowerCase();
  if (typed != 'leave_request' && typed != 'leave request') {
    throw const SocketCallError(
      'not_found',
      'No such structure, or it is not available to you.',
    );
  }
  return {
    'tstruct': {'name': 'leave_request', ..._leave},
    'scope': 'user',
    'rev': '1',
  };
}

SubmissionRepository _repo(FakeSocket socket, FakeStore store, _Db db) =>
    SubmissionRepository(db, store, socket, _Messages(), _Options());

FormCardData _card({
  String id = '12',
  String by = 'me',
  String? status,
  bool canResubmit = false,
  String? forwardedBy,
}) => FormCardData(
  id: id,
  caption: 'Leave Request',
  structure: 'leave_request',
  scope: 'user',
  by: by,
  ts: 0,
  entries: const [],
  status: status,
  canResubmit: canResubmit,
  forwardedBy: forwardedBy,
);

void main() {
  late FakeSocket socket;
  late FakeStore store;
  late _Db db;
  late SubmissionRepository repo;

  setUp(() {
    socket = FakeSocket()..goOnline();
    store = FakeStore();
    db = _Db();
    repo = _repo(socket, store, db);
    socket.answers['tstruct.user.open'] = _opened;
    socket.answers['submissions.list'] = const SocketCallError('rate_limited');
  });

  group('tstruct.user.open', () {
    test(
      'one request per open: the typed text and mode add, nothing else',
      () async {
        expect(socket.count('tstruct.user.open'), 0);
        final open = await repo.openStructure('  Leave Request ');
        expect(open.isOpen, isTrue);
        expect(open.name, 'leave_request');
        expect(open.scope, 'user');
        expect(open.caption, 'Leave Request');
        expect(socket.calls, hasLength(1));
        expect(socket.calls.single.action, 'tstruct.user.open');
        expect(socket.calls.single.args, {
          'name': 'Leave Request',
          'mode': 'add',
        });
      },
    );

    test(
      'a caption typed by hand resolves like the web: sent whole, not split',
      () async {
        final open = await repo.openStructure('leave request');
        expect(open.name, 'leave_request');
        expect(socket.calls.single.args['name'], 'leave request');
      },
    );

    test(
      'the definition is kept for the form screen to reuse for 30 s',
      () async {
        await repo.openStructure('leave_request');
        final def = repo.definitions['leave_request']!;
        expect(def.isFull, isTrue);
        final age = DateTime.now().millisecondsSinceEpoch - def.fetchedTs;
        expect(age, lessThan(FormController.openedAge.inMilliseconds));
        expect(db.defs, hasLength(1));
        expect(socket.count('tstruct.user.open'), 1);
      },
    );

    test(
      'a name the server does not know is refused with its own words',
      () async {
        final open = await repo.openStructure('nope');
        expect(open.isOpen, isFalse);
        expect(open.code, 'not_found');
        expect(open.message, contains('No such structure'));
      },
    );

    test('empty text is the usage case and asks nothing', () async {
      final open = await repo.openStructure('   ');
      expect(open.isUsage, isTrue);
      expect(socket.calls, isEmpty);
    });

    test(
      'offline with the form kept on the device opens it, by name or caption',
      () async {
        await repo.openStructure('leave_request');
        socket.goOffline();
        for (final typed in ['leave_request', 'LEAVE request']) {
          final open = await repo.openStructure(typed);
          expect(open.isOpen, isTrue, reason: typed);
          expect(open.name, 'leave_request');
        }
        expect(socket.count('tstruct.user.open'), 1);
      },
    );

    test(
      'offline with the form kept on disk only (after a restart) opens it',
      () async {
        await repo.openStructure('leave_request');
        final restarted = _repo(socket, store, db);
        await restarted.reload();
        socket.goOffline();
        expect((await restarted.openStructure('Leave Request')).isOpen, isTrue);
      },
    );

    test('offline with nothing kept says so and fetches nothing', () async {
      socket.goOffline();
      final open = await repo.openStructure('leave_request');
      expect(open.isOpen, isFalse);
      expect(open.isOffline, isTrue);
      expect(socket.calls, isEmpty);
    });

    test(
      'kept per organisation: another organisation sees none of it',
      () async {
        repo.onInit();
        await repo.openStructure('leave_request');
        await repo.reload();
        expect(repo.definitions.keys, ['leave_request']);

        store.switchTo('me', org: 'other-org');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.definitions, isEmpty);
        socket.goOffline();
        final open = await repo.openStructure('leave_request');
        expect(open.isOpen, isFalse);
        expect(open.isOffline, isTrue);

        store.switchTo('me');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.definitions.keys, ['leave_request']);
      },
    );
  });

  group('the submit request', () {
    final payload = {
      'name': 'leave_request',
      'values': {'reason': 'Fever'},
      'chat': null,
    };

    test('name, values and cid; no chat, ref or meta when unticked', () {
      final args = SubmissionRepository.submitArgs(payload, 'm-1');
      expect(args, {
        'name': 'leave_request',
        'values': {'reason': 'Fever'},
        'cid': 'm-1',
      });
      expect(args.containsKey('ref'), isFalse);
      expect(args.containsKey('meta'), isFalse);
    });

    test('chat only when the box was ticked', () {
      final args = SubmissionRepository.submitArgs({
        ...payload,
        'chat': 'dm:ana',
      }, 'm-1');
      expect(args['chat'], 'dm:ana');
      expect(args.keys.toSet(), {'name', 'values', 'chat', 'cid'});
    });

    test('the action follows the form scope', () async {
      expect(SubmissionRepository.submitCommand('user'), 'tstruct.user.submit');
      expect(SubmissionRepository.submitCommand('admin'), 'tstruct.submit');
      await socket.sdCall(
        SubmissionRepository.submitCommand('user'),
        SubmissionRepository.submitArgs(payload, 'm-9'),
      );
      expect(socket.calls.single.args['cid'], 'm-9');
    });
  });

  group('the also-post box', () {
    FormController controller(FormLaunch launch) => FormController(
      launch: launch,
      submissions: repo,
      options: _Options(),
      store: store,
      connectivity: FakeConnectivity(),
      logic: _Logic(),
      files: FakeFiles(),
    );

    FormLaunch hashLaunch({bool isDefault = false, String? conv = 'dm:ana'}) =>
        FormLaunch(
          name: 'leave_request',
          scope: 'user',
          caption: 'Leave Request',
          convId: conv,
          postChoiceTitle: conv == null ? null : 'Ana',
          isPostedByDefault: isDefault,
        );

    test('unticked by default: no chat is sent', () {
      final c = controller(hashLaunch());
      expect(c.isPostedToChat.value, isFalse);
      expect(c.chatToSend, isNull);
    });

    test('ticked: the chat is sent', () {
      final c = controller(hashLaunch());
      c.isPostedToChat.value = true;
      expect(c.chatToSend, 'dm:ana');
    });

    test('an encrypted chat: the box works the same, chat sent when ticked', () {
      final c = controller(
        FormLaunch(
          name: 'leave_request',
          scope: 'user',
          caption: 'Leave Request',
          convId: 'group:sales',
          postChoiceTitle: 'Sales',
          isEncryptedChat: true,
        ),
      );
      expect(c.chatToSend, isNull);
      c.isPostedToChat.value = true;
      expect(c.chatToSend, 'group:sales');
    });

    test('ticked by default in a care thread, and can be unticked', () {
      final c = controller(hashLaunch(isDefault: true, conv: 'group:care-ana'));
      expect(c.chatToSend, 'group:care-ana');
      c.isPostedToChat.value = false;
      expect(c.chatToSend, isNull);
    });

    test('the forms button always posts into its chat (no choice offered)', () {
      final c = controller(
        FormLaunch(
          name: 'leave_request',
          scope: 'user',
          caption: 'Leave',
          convId: 'dm:ana',
        ),
      );
      expect(c.chatToSend, 'dm:ana');
    });

    test('from the Work Space nothing is posted', () {
      final c = controller(hashLaunch(conv: null));
      expect(c.launch.hasPostChoice, isFalse);
      expect(c.chatToSend, isNull);
    });
  });

  group('edit and delete rules', () {
    test('delete: mine, sent, not waiting for approval, not approved', () {
      expect(_card().canDelete('me'), isTrue);
      expect(_card(status: 'rejected').canDelete('me'), isTrue);
      expect(_card(status: 'pending').canDelete('me'), isFalse);
      expect(_card(status: 'approved').canDelete('me'), isFalse);
      expect(_card(by: 'ana').canDelete('me'), isFalse);
      expect(_card(id: 'temp-5').canDelete('me'), isFalse);
      expect(_card(forwardedBy: 'ana').canDelete('me'), isFalse);
    });

    test(
      'edit: refused while pending or approved, a declined one is fixed',
      () {
        expect(_card().canEdit('me'), isTrue);
        expect(_card(status: 'pending').canEdit('me'), isFalse);
        expect(_card(status: 'approved').canEdit('me'), isFalse);
        expect(_card(status: 'rejected').canEdit('me'), isFalse);
        expect(
          _card(status: 'rejected', canResubmit: true).canFix('me'),
          isTrue,
        );
        expect(_card(status: 'rejected').canFix('me'), isFalse);
        expect(_card(by: 'ana').canEdit('me'), isFalse);
      },
    );
  });

  group('submissions.delete', () {
    setUp(() {
      repo.submissions.add(
        FormSubmission(
          submissionId: '12',
          tstruct: 'leave_request',
          byUser: 'me',
          ts: 1,
          valuesJson: '{}',
          syncState: 'synced',
        ),
      );
    });

    test('sends the numeric id, drops the row and says nothing', () async {
      final problem = await repo.deleteSubmission('12');
      expect(problem, isNull);
      expect(socket.calls.first.action, 'submissions.delete');
      expect(socket.calls.first.args, {'id': 12});
      expect(repo.submissions, isEmpty);
    });

    test(
      'submission_locked is told in plain words and the row stays',
      () async {
        socket.answers['submissions.delete'] = const SocketCallError(
          'submission_locked',
          'raw server text',
        );
        final problem = await repo.deleteSubmission('12');
        expect(problem, contains("can't be deleted"));
        expect(problem, isNot(contains('raw server text')));
        expect(repo.submissions, hasLength(1));
      },
    );

    test('forbidden is told in plain words', () async {
      socket.answers['submissions.delete'] = const SocketCallError('forbidden');
      expect(await repo.deleteSubmission('12'), contains('Only the person'));
      expect(repo.submissions, hasLength(1));
    });

    test('not_found: it is gone, so it leaves the list too', () async {
      socket.answers['submissions.delete'] = const SocketCallError('not_found');
      expect(await repo.deleteSubmission('12'), contains('no longer exists'));
    });

    test('offline asks for a connection and sends nothing', () async {
      socket.goOffline();
      expect(await repo.deleteSubmission('12'), 'Needs a connection');
      expect(socket.calls, isEmpty);
      expect(repo.submissions, hasLength(1));
    });

    test(
      'a submission not sent yet cannot be deleted from the server',
      () async {
        expect(await repo.deleteSubmission('temp-1'), isNotNull);
        expect(socket.calls, isEmpty);
      },
    );
  });

  group('field types', () {
    test('a status field (statusLocked) is not shown and not sent', () {
      final def = FormDefinition.fromMap('help_ticket', 'user', {
        'caption': 'Ticket',
        'fields': [
          {'name': 'title', 'caption': 'Title', 'type': 'text'},
          {
            'name': 'stage',
            'caption': 'Stage',
            'type': 'list',
            'options': ['Open', 'Done'],
            'statusLocked': true,
          },
        ],
      });
      final c = FormController(
        launch: FormLaunch(name: 'help_ticket', scope: 'user', caption: 'T'),
        submissions: repo,
        options: _Options(),
        store: store,
        connectivity: FakeConnectivity(),
        logic: _Logic(),
        files: FakeFiles(),
      )..definition = def;
      expect(c.isVisible(def.fieldOf('title')!), isTrue);
      expect(c.isVisible(def.fieldOf('stage')!), isFalse);
    });
  });

  group('a real navigation: composer, #create, form, back', () {
    testWidgets(
      '#create opens the form, saving returns to the Work Space with "Saved"',
      (tester) async {
        final commands = _Commands();
        final subs = _Subs();
        final notice = SavedRecordNotice(subs, _Tickets())..onInit();
        final runner = CommandRunner(
          commands,
          CommandPrompt(commands),
          submissions: subs,
          shell: _Shell(),
        );
        await tester.pumpWidget(
          GetMaterialApp(
            builder: (context, child) => AppNoticeHost(child: child!),
            home: Scaffold(
              body: Column(
                children: [
                  const Text('Work Space'),
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => runner.run('#create Leave Request'),
                      child: const Text('send'),
                    ),
                  ),
                ],
              ),
            ),
            getPages: [
              GetPage(
                name: AppRoutes.form,
                page: () => Scaffold(
                  body: Column(
                    children: [
                      const Text('Leave form'),
                      TextButton(
                        onPressed: () {
                          subs.emit(
                            const SavedRecord(id: 7, tstruct: 'leave_request'),
                          );
                          Get.back<bool>(result: true);
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        await tester.tap(find.text('send'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Leave form'), findsOneWidget);
        expect(subs.asked, ['Leave Request']);

        await tester.tap(find.text('Done'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Leave form'), findsNothing);
        expect(find.text('Work Space'), findsOneWidget);
        expect(find.text('Saved'), findsOneWidget);
        notice.onClose();
        await tester.pump(const Duration(seconds: 6));
      },
    );

    testWidgets('#ts shows the submissions of that form only', (tester) async {
      final shell = _Shell();
      final list = _Subs();
      list.submissions.assignAll([
        for (final (id, name) in [('1', 'leave_request'), ('2', 'expense')])
          FormSubmission(
            submissionId: id,
            tstruct: name,
            byUser: 'me',
            ts: 1,
            valuesJson: jsonEncode({'x': id}),
            syncState: 'synced',
          ),
      ]);
      list.isLoaded.value = true;
      final controller = SubmissionsController(
        submissions: list,
        connectivity: FakeConnectivity(),
        shell: shell,
      );
      controller.onInit();
      expect(controller.rows, hasLength(2));

      final commands = _Commands()..line = HashKind.records;
      final runner = CommandRunner(
        commands,
        CommandPrompt(commands),
        submissions: list,
        shell: shell,
      );
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      await tester.runAsync(() => runner.run('#ts Leave Request'));
      await tester.pump();
      expect(shell.opened, ['leave_request']);
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.rows.map((r) => r.card.structure), ['leave_request']);
      controller.onClose();
    });
  });

  group('delete from the detail screen', () {
    testWidgets('asks first; a refusal is a notice and the card stays', (
      tester,
    ) async {
      final subs = _Subs()..deleteAnswer = 'It cannot be deleted';
      final c = SubmissionDetailController(
        submissionId: '12',
        submissions: subs,
        store: store,
      )..card.value = _card();
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));

      await tester.runAsync(() => c.delete(() async => false));
      expect(subs.deleted, isEmpty);

      await tester.runAsync(() => c.delete(() async => true));
      expect(subs.deleted, ['12']);
      expect(c.card.value, isNotNull);
      expect(c.isDeleting.value, isFalse);
    });

    testWidgets('nothing is asked for a record that cannot be deleted', (
      tester,
    ) async {
      final subs = _Subs();
      final c = SubmissionDetailController(
        submissionId: '12',
        submissions: subs,
        store: store,
      )..card.value = _card(status: 'approved');
      await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
      var isAsked = false;
      await tester.runAsync(
        () => c.delete(() async {
          isAsked = true;
          return true;
        }),
      );
      expect(isAsked, isFalse);
      expect(c.canDelete, isFalse);
    });
  });
}

class _Logic extends Fake implements FormLogicService {}

class _Commands extends Fake implements CommandRepository {
  HashKind line = HashKind.form;

  @override
  CommandSuggester createSuggester() =>
      CommandSuggester((_, _, _) async => null);

  @override
  Future<HashResult> run(
    String line, {
    String? activeConvId,
    bool isConfirmed = false,
  }) async => HashResult(
    this.line,
    '',
    '',
    '',
    '',
    const [],
    const [],
    'Leave Request',
  );
}

class _Subs extends Fake implements SubmissionRepository {
  @override
  final submissions = <FormSubmission>[].obs;
  @override
  final definitions = <String, FormDefinition>{}.obs;
  @override
  final isLoaded = true.obs;
  final _savedController = StreamController<SavedRecord>.broadcast();
  void emit(SavedRecord r) => _savedController.add(r);
  final asked = <String>[];
  final deleted = <String>[];
  String? deleteAnswer;

  @override
  Stream<SavedRecord> get saved => _savedController.stream;

  @override
  Future<StructureOpen> openStructure(String typed) async {
    asked.add(typed);
    return const StructureOpen('leave_request', 'user', 'Leave Request');
  }

  @override
  Future<bool> syncFromServer() async => true;

  @override
  Future<void> reload() async {}

  @override
  Future<String?> deleteSubmission(String id) async {
    deleted.add(id);
    return deleteAnswer;
  }
}

class _Shell extends Fake implements HomeShellController {
  @override
  final submissionsForm = RxnString();
  @override
  final index = 0.obs;

  final opened = <String>[];

  @override
  void openSubmissionsOf(String formName) {
    opened.add(formName);
    submissionsForm.value = formName;
  }
}

class _Tickets extends Fake implements TicketRepository {
  @override
  Future<RecordState?> afterSave(int id) async => null;
}
