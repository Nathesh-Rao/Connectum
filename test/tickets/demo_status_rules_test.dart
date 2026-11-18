import 'package:connectum/core/debug/seed_tickets.dart';
import 'package:connectum/core/debug/seed_ui.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await SeedTickets.start();
    addTearDown(SeedTickets.stop);
  });

  test('the demo form has an Auto Fill field of the date kind', () {
    final f = SeedUi.createFlowForms()['help_ticket']!.fieldOf('due_on')!;
    expect(f.isAutoFill, isTrue);
    expect(f.kind, 'date');
  });

  test('record.actions carries finalStatuses and minCompletion', () {
    final member = SeedTickets.answer(RecordCmd.actions, {'id': 32});
    expect(member['finalStatuses'], ['Done']);
    expect(member['minCompletion'], 40);
    final admin = SeedTickets.answer(RecordCmd.actions, {'id': 44});
    expect(admin['isAdmin'], isTrue);
    expect(admin['status'], 'Done');
    expect(admin['completion'], 100);
    expect(admin['minCompletion'], 0);
    expect(
      (admin['items'] as List).firstWhere(
        (i) => i['id'] == 'status',
      )['enabled'],
      isTrue,
    );
  });

  test('closing writes 100; 100 on a status that does not close is refused', () {
    expect(
      () => SeedTickets.answer(RecordCmd.status, {
        'id': 32,
        'status': 'Open',
        'percent': 100,
      }),
      throwsA(
        isA<SocketCallError>().having(
          (e) => e.message,
          'message',
          '100% completion is only for a closing status. Choose a closing status.',
        ),
      ),
    );
    final done = SeedTickets.answer(RecordCmd.status, {
      'id': 32,
      'status': 'Done',
    });
    expect(done['completion'], 100);
    expect(done['final'], isTrue);
  });

  test('an administrator reopening a closed record gets 99', () {
    final out = SeedTickets.answer(RecordCmd.status, {
      'id': 44,
      'status': 'Open',
    });
    expect(out['completion'], 99);
    expect(out['final'], isFalse);
  });

  test('records.summary answers the record object', () {
    final out = SeedTickets.answer(RecordCmd.summary, {
      'ids': [32, 44, 999],
    });
    expect((out['summaries'] as List).length, 2);
    expect(out['omitted'], 1);
    final rec = (out['summaries'] as List).first['record'] as Map;
    expect(
      rec.keys,
      containsAll([
        'status',
        'holder',
        'claimants',
        'completion',
        'final',
        'ts',
        'by',
      ]),
    );
  });
}
