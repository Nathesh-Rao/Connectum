import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/data/socket/call_problem.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/models/ticket_input.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ticket_fixtures.dart';

final _table = TicketForm.parseAll(
  fixtureData('status_mine_with')['structures'],
)['help_ticket']!.table!;

TicketAction action(String name) =>
    _table.actions.firstWhere((a) => a.name == name);

Map<String, dynamic> build(
  String name,
  TicketActionInput input, {
  String requestId = 'r1',
}) => TicketPayload.build(
  id: 38,
  action: action(name),
  input: input,
  requestId: requestId,
  expectedStatus: 'Open',
  expectedAssignee: 'ana',
);

CallProblem problem(String code, [String message = 'm']) =>
    CallProblem.of(SocketCallError(code, message), isWrite: true);

void main() {
  group('payload builder', () {
    test('expected and requestId are always there', () {
      final p = build('Take it', const TicketActionInput());
      expect(p, {
        'id': 38,
        'action': 'Take it',
        'expected': {'status': 'Open', 'assignee': 'ana'},
        'requestId': 'r1',
      });
    });

    test('Send: remarks and sendTo, nothing else', () {
      final p = build(
        'Send',
        const TicketActionInput(
          remarks: ' your area ',
          sendTo: 'ben',
          reason: 'ignored',
          percent: 50,
          files: ['f'],
        ),
      );
      expect(p['remarks'], 'your area');
      expect(p['sendTo'], 'ben');
      expect(p.containsKey('reason'), isFalse);
      expect(p.containsKey('percent'), isFalse);
      expect(p.containsKey('files'), isFalse);
    });

    test('Status update: percent and optional remarks', () {
      final p = build(
        'Status update',
        const TicketActionInput(percent: 30, remarks: 'started'),
      );
      expect(p['percent'], 30);
      expect(p['remarks'], 'started');
      expect(p.containsKey('sendTo'), isFalse);
    });

    test('an empty optional remark is left out', () {
      final p = build('Status update', const TicketActionInput(percent: 10));
      expect(p.containsKey('remarks'), isFalse);
    });

    test('Complete: percent hundred sends no percent', () {
      final p = build('Complete', const TicketActionInput(percent: 77));
      expect(p.containsKey('percent'), isFalse);
    });

    test('Return: reason and remarks', () {
      final p = build(
        'Return',
        const TicketActionInput(reason: 'Wrong team', remarks: 'not mine'),
      );
      expect(p['reason'], 'Wrong team');
      expect(p['remarks'], 'not mine');
    });

    test('files go in when the action takes them', () {
      const withFiles = TicketAction(name: 'Attach', attachments: 'optional');
      final p = TicketPayload.build(
        id: 1,
        action: withFiles,
        input: const TicketActionInput(files: ['a', 'b']),
        requestId: 'r',
        expectedStatus: 'Open',
        expectedAssignee: 'x',
      );
      expect(p['files'], ['a', 'b']);
    });

    test('a retry reuses the same request id', () {
      const input = TicketActionInput(remarks: 'x', sendTo: 'ben');
      final first = build('Send', input, requestId: 'same');
      final retry = build('Send', input, requestId: 'same');
      expect(retry['requestId'], first['requestId']);
      expect(retry, first);
    });
  });

  group('validation', () {
    test('required remarks block until filled', () {
      expect(
        TicketValidation.check(
          action('Send'),
          const TicketActionInput(sendTo: 'ben'),
        ),
        TicketValidation.remarksRequired,
      );
      expect(
        TicketValidation.check(
          action('Send'),
          const TicketActionInput(sendTo: 'ben', remarks: '  '),
        ),
        TicketValidation.remarksRequired,
      );
      expect(
        TicketValidation.check(
          action('Send'),
          const TicketActionInput(sendTo: 'ben', remarks: 'ok'),
        ),
        isNull,
      );
    });

    test('required reason and remarks', () {
      expect(
        TicketValidation.check(
          action('Return'),
          const TicketActionInput(remarks: 'x'),
        ),
        TicketValidation.reasonRequired,
      );
      expect(
        TicketValidation.check(
          action('Return'),
          const TicketActionInput(reason: 'r'),
        ),
        TicketValidation.remarksRequired,
      );
      expect(
        TicketValidation.check(
          action('Return'),
          const TicketActionInput(reason: 'r', remarks: 'x'),
        ),
        isNull,
      );
    });

    test('optional inputs may stay empty', () {
      expect(
        TicketValidation.check(
          action('Status update'),
          const TicketActionInput(),
        ),
        isNull,
      );
      expect(
        TicketValidation.check(action('Close'), const TicketActionInput()),
        isNull,
      );
    });

    test('percent must be 0 to 100', () {
      expect(
        TicketValidation.check(
          action('Status update'),
          const TicketActionInput(percent: 101),
        ),
        TicketValidation.percentRange,
      );
      expect(
        TicketValidation.check(
          action('Status update'),
          const TicketActionInput(percent: -1),
        ),
        TicketValidation.percentRange,
      );
      expect(
        TicketValidation.check(
          action('Status update'),
          const TicketActionInput(percent: 100),
        ),
        isNull,
      );
    });

    test('sendTo is needed when assign is pick', () {
      expect(
        TicketValidation.check(
          action('Send'),
          const TicketActionInput(remarks: 'x'),
        ),
        TicketValidation.sendToRequired,
      );
    });

    test('a reason must come from the list when there is one', () {
      const a = TicketAction(
        name: 'Return',
        reason: 'required',
        reasons: ['A', 'B'],
      );
      expect(
        TicketValidation.check(a, const TicketActionInput(reason: 'C')),
        TicketValidation.reasonRequired,
      );
      expect(
        TicketValidation.check(a, const TicketActionInput(reason: 'A')),
        isNull,
      );
    });

    test('a required file', () {
      const a = TicketAction(name: 'Proof', attachments: 'required');
      expect(
        TicketValidation.check(a, const TicketActionInput()),
        TicketValidation.fileRequired,
      );
      expect(
        TicketValidation.check(a, const TicketActionInput(files: ['f'])),
        isNull,
      );
    });
  });

  group('error mapping', () {
    test('stale: reload, keep what was typed, fresh request id next time', () {
      final p = problem(
        'stale',
        'This ticket was updated by someone else. Reload to see the latest.',
      );
      expect(p.kind, CallProblemKind.stale);
      expect(p.text, startsWith('This ticket was updated'));
      final o = TicketOutcome.of(p);
      expect(o.isSuccess, isFalse);
      expect(o.shouldReload, isTrue);
      expect(o.shouldKeepForm, isTrue);
      expect(o.shouldKeepRequestId, isFalse);
      expect(o.canRetry, isFalse);
    });

    test('duplicate is success', () {
      final o = TicketOutcome.of(problem('duplicate'));
      expect(o.isSuccess, isTrue);
    });

    test('forbidden: server text, refresh, keep the form', () {
      final p = problem('forbidden', 'You cannot do this on this ticket.');
      expect(p.text, 'You cannot do this on this ticket.');
      final o = TicketOutcome.of(p);
      expect(o.shouldReload, isTrue);
      expect(o.canRetry, isFalse);
      expect(o.shouldKeepRequestId, isFalse);
    });

    test('invalid refreshes too', () {
      expect(TicketOutcome.of(problem('invalid')).shouldReload, isTrue);
    });

    test('not_found removes the row', () {
      final o = TicketOutcome.of(problem('not_found', 'No such ticket.'));
      expect(o.shouldRemoveRow, isTrue);
    });

    test('busy and rate_limited: manual retry with the same request id', () {
      for (final code in ['busy', 'rate_limited']) {
        final o = TicketOutcome.of(problem(code, 'slow down'));
        expect(o.canRetry, isTrue);
        expect(o.shouldKeepRequestId, isTrue);
        expect(o.shouldKeepForm, isTrue);
        expect(o.shouldReload, isFalse);
      }
    });

    test('a lost answer: retry with the same request id, and read again', () {
      final p = problem('timeout');
      expect(p.kind, CallProblemKind.unknownOutcome);
      final o = TicketOutcome.of(p);
      expect(o.canRetry, isTrue);
      expect(o.shouldKeepRequestId, isTrue);
      expect(o.shouldReload, isTrue);
    });

    test('offline: retry, same request id', () {
      final o = TicketOutcome.of(problem('not_connected'));
      expect(o.canRetry, isTrue);
      expect(o.shouldKeepRequestId, isTrue);
    });

    test('the server text is always verbatim', () {
      for (final code in [
        'invalid',
        'not_found',
        'duplicate',
        'busy',
        'rate_limited',
        'other',
      ]) {
        expect(problem(code, 'Exactly this.').text, 'Exactly this.');
      }
    });
  });
}
