import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/socket/call_problem.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/tickets/models/ticket_input.dart';
import 'package:flutter_test/flutter_test.dart';

RecordState state({
  bool comments = false,
  bool completion = false,
  bool hours = false,
  bool files = false,
  bool admin = false,
  int? done,
}) => RecordState(
  items: const [],
  status: 'Open',
  statuses: const ['Open', 'In progress', 'Done'],
  finalStatuses: const ['Done'],
  completion: done,
  isCommentsRequired: comments,
  isCompletionRequired: completion,
  isHoursRequired: hours,
  isFilesRequired: files,
  isAdmin: admin,
);

CallProblem problem(String code, {bool isWrite = true}) =>
    CallProblem.of(SocketCallError(code, 'm'), isWrite: isWrite);

void main() {
  group('status validation uses the BE wording', () {
    test('a status of the record is needed', () {
      expect(
        RecordValidation.status(state(), const StatusInput()),
        'Choose one of the statuses of this record.',
      );
      expect(
        RecordValidation.status(state(), const StatusInput(status: 'Nope')),
        RecordValidation.statusRequired,
      );
      expect(
        RecordValidation.status(state(), const StatusInput(status: 'Done')),
        isNull,
      );
    });

    test('required fields from record.actions are mandatory', () {
      const base = StatusInput(status: 'Done');
      final s = state(
        comments: true,
        completion: true,
        hours: true,
        files: true,
      );
      expect(RecordValidation.status(s, base), 'Add your comments.');
      expect(
        RecordValidation.status(
          s,
          const StatusInput(status: 'Done', comments: 'x'),
        ),
        'Enter the completion.',
      );
      expect(
        RecordValidation.status(
          s,
          const StatusInput(status: 'Done', comments: 'x', percent: 0),
        ),
        'Enter the hours worked.',
      );
      expect(
        RecordValidation.status(
          s,
          const StatusInput(
            status: 'Done',
            comments: 'x',
            percent: 0,
            hours: '0',
          ),
        ),
        'Attach a file.',
      );
      expect(
        RecordValidation.status(
          s,
          const StatusInput(
            status: 'Done',
            comments: 'x',
            percent: 0,
            hours: '0',
            files: ['f'],
          ),
        ),
        isNull,
      );
    });

    test(
      'spaces are not a comment; a completion of 0 and hours of 0 count',
      () {
        expect(
          RecordValidation.status(
            state(comments: true),
            const StatusInput(status: 'Done', comments: '   '),
          ),
          'Add your comments.',
        );
        expect(
          RecordValidation.status(
            state(completion: true, hours: true),
            const StatusInput(status: 'Done', percent: 0, hours: '0'),
          ),
          isNull,
        );
      },
    );

    test('the completion cannot go down, except for an administrator', () {
      const input = StatusInput(status: 'Done', percent: 20);
      expect(
        RecordValidation.status(state(done: 40), input),
        'Completion cannot go down.',
      );
      expect(
        RecordValidation.status(state(done: 40, admin: true), input),
        isNull,
      );
      expect(
        RecordValidation.status(
          state(),
          const StatusInput(status: 'Done', percent: 101),
        ),
        'Completion is 0 to 100.',
      );
    });

    test('hours: 0 to 24 with at most two decimals', () {
      String? check(String h) => RecordValidation.status(
        state(),
        StatusInput(status: 'Done', hours: h),
      );
      expect(check('24'), isNull);
      expect(check('2.5'), isNull);
      expect(check('2,25'), isNull);
      expect(check('0'), isNull);
      expect(check('24.5'), RecordValidation.hoursRange);
      expect(check('2.555'), RecordValidation.hoursRange);
      expect(check('-1'), RecordValidation.hoursRange);
      expect(check('abc'), RecordValidation.hoursRange);
    });

    test('comments at most 1,000 characters; files at most 10', () {
      expect(
        RecordValidation.status(
          state(),
          StatusInput(status: 'Done', comments: 'x' * 1001),
        ),
        RecordValidation.commentsLong,
      );
      expect(
        RecordValidation.status(
          state(),
          StatusInput(status: 'Done', comments: 'x' * 1000),
        ),
        isNull,
      );
      expect(
        RecordValidation.status(
          state(),
          StatusInput(
            status: 'Done',
            files: [for (var i = 0; i < 11; i++) '$i'],
          ),
        ),
        RecordValidation.tooManyFiles,
      );
    });
  });

  group('send validation', () {
    test('every via needs its value', () {
      String? check(SendInput i) => RecordValidation.send(i);
      expect(check(const SendInput()), RecordValidation.sendToRequired);
      expect(
        check(const SendInput(via: 'user')),
        RecordValidation.sendToRequired,
      );
      expect(check(const SendInput(via: 'user', person: 'ben')), isNull);
      expect(
        check(const SendInput(via: 'designation')),
        RecordValidation.sendToRequired,
      );
      expect(check(const SendInput(via: 'designation', value: 'Tech')), isNull);
      expect(check(const SendInput(via: 'category', value: 'C')), isNull);
      expect(check(const SendInput(via: 'initiator')), isNull);
      expect(check(const SendInput(via: 'assignor')), isNull);
    });

    test('reason and remarks at most 1,000 characters', () {
      expect(
        RecordValidation.send(SendInput(via: 'initiator', reason: 'x' * 1001)),
        RecordValidation.textLong,
      );
      expect(
        RecordValidation.send(SendInput(via: 'initiator', remarks: 'x' * 1001)),
        RecordValidation.textLong,
      );
    });
  });

  group('outcomes are decided by the code', () {
    test('stale: read again, keep what was typed', () {
      final o = TicketOutcome.of(problem('stale'));
      expect(o.shouldReload, isTrue);
      expect(o.isSuccess, isFalse);
      expect(o.shouldKeepRequestId, isFalse);
    });

    test('not_found: leave and refresh the list', () {
      expect(TicketOutcome.of(problem('not_found')).shouldLeave, isTrue);
    });

    test('busy: one automatic retry with the same request id', () {
      final o = TicketOutcome.of(problem('busy'));
      expect(o.shouldRetryOnce, isTrue);
      expect(o.shouldKeepRequestId, isTrue);
    });

    test('rate_limited: a short back-off, same request id', () {
      final o = TicketOutcome.of(problem('rate_limited'));
      expect(o.shouldBackOff, isTrue);
      expect(o.shouldKeepRequestId, isTrue);
      expect(o.canRetry, isTrue);
    });

    test('forbidden shows the text and reads again', () {
      final o = TicketOutcome.of(problem('forbidden'));
      expect(o.shouldReload, isTrue);
      expect(o.shouldKeepRequestId, isFalse);
    });

    test('invalid and bad_request only show their message', () {
      for (final code in ['invalid', 'bad_request']) {
        final o = TicketOutcome.of(problem(code));
        expect(o.shouldReload || o.shouldLeave || o.canRetry, isFalse);
      }
    });

    test(
      'a lost answer: the same request id is kept and the record is read',
      () {
        final o = TicketOutcome.of(problem('timeout'));
        expect(o.shouldKeepRequestId, isTrue);
        expect(o.shouldReload, isTrue);
      },
    );

    test('the words never decide', () {
      final a = CallProblem.of(
        const SocketCallError('stale', 'Something else entirely.'),
      );
      expect(TicketOutcome.of(a).shouldReload, isTrue);
    });
  });

  test('the limits are the ones the server states', () {
    expect(RecordLimits.maxFiles, 10);
    expect(RecordLimits.maxText, 1000);
    expect(RecordLimits.maxFileBytes, 10 * 1024 * 1024);
  });
}
