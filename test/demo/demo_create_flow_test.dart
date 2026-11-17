import 'package:connectum/core/debug/seed_tickets.dart';
import 'package:connectum/core/debug/seed_ui.dart';
import 'package:connectum/data/db/app_database.dart';
import 'package:connectum/data/models/form_definition.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/form_options_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/features/forms/form_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Db extends Fake implements AppDatabase {
  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async => [];
}

class _Options extends Fake implements FormOptionsRepository {}

class _Messages extends Fake implements MessageRepository {}

/// The demo structures for `#create <name>` offline. The data checks always
/// run; the ones that need the demo switched on run with
/// `flutter test --dart-define=DEMO_MODE=true test/demo/demo_create_flow_test.dart`.
void main() {
  final forms = SeedUi.createFlowForms();

  test(
    'the demo has a ticket, a work order and a form with an unsupported type',
    () {
      expect(
        forms.keys,
        containsAll(['help_ticket', 'help_task', 'asset_check']),
      );
      expect(forms['help_ticket']!.caption, 'Ticket');
      expect(
        forms['help_ticket']!.fieldOf('stage')!.raw['statusLocked'],
        isTrue,
      );
    },
  );

  test('exactly one field type is one the form screen cannot fill', () {
    final unsupported = [
      for (final d in forms.values)
        for (final FormFieldDef f in d.fields)
          if (!FormRules.isSupported(f)) f.type,
    ];
    expect(unsupported, ['signature']);
    final signature = forms['asset_check']!.fieldOf('signature')!;
    expect(signature.isRequired, isFalse);
  });

  group('with the demo on', () {
    final isDemo = SeedUi.isActive;
    late SubmissionRepository repo;
    late FakeSocket socket;

    setUp(() async {
      socket = FakeSocket()..goOnline();
      repo = SubmissionRepository(
        _Db(),
        FakeStore(),
        socket,
        _Messages(),
        _Options(),
      );
      await repo.reload();
      await SeedTickets.start();
    });

    test('#create opens by name or caption; a wrong name is refused', () async {
      for (final typed in [
        'help_ticket',
        'ticket',
        'Work order',
        'asset check',
      ]) {
        expect((await repo.openStructure(typed)).isOpen, isTrue, reason: typed);
      }
      final wrong = await repo.openStructure('nothing here');
      expect(wrong.isOpen, isFalse);
      expect(wrong.code, 'not_found');
      expect(socket.calls, isEmpty, reason: 'the demo never asks a server');
    }, skip: !isDemo);

    test(
      'a saved ticket is held by someone, and says so through the record calls',
      () async {
        final saved = repo.saved.first;
        await repo.submitForm(
          'help_ticket',
          {'title': 'Projector bulb'},
          cid: 'm-demo-1',
          caption: 'Ticket',
        );
        final record = await saved.timeout(const Duration(seconds: 5));
        expect(record.tstruct, 'help_ticket');
        final actions = SeedTickets.answer(RecordCmd.actions, {
          'id': record.id,
        });
        expect(actions['holder'], 'sam');
        final history = SeedTickets.answer(RecordCmd.history, {
          'id': record.id,
        });
        expect(history['events'] ?? history['history'] ?? history, isNotNull);
      },
      skip: !isDemo,
    );

    test(
      'a work order asks for comments, completion, hours and a file',
      () {
        final id = SeedTickets.addFromForm('help_task', {'title': 'Chairs'});
        final a = SeedTickets.answer(RecordCmd.actions, {'id': id});
        expect(a['commentsRequired'], isTrue);
        expect(a['completionRequired'], isTrue);
        expect(a['hoursRequired'], isTrue);
        expect(a['filesRequired'], isTrue);
      },
      skip: !isDemo,
    );
  });
}
