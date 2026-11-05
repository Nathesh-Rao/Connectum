import 'package:connectum/data/socket/call_problem.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every error code the docs name, with the follow-up the screens act on.
void main() {
  const table =
      <({String code, CallProblemKind kind, bool retry, bool refresh})>[
        (
          code: 'rate_limited',
          kind: CallProblemKind.rateLimited,
          retry: true,
          refresh: false,
        ),
        (code: 'busy', kind: CallProblemKind.busy, retry: true, refresh: false),
        (
          code: 'stale',
          kind: CallProblemKind.stale,
          retry: false,
          refresh: true,
        ),
        (
          code: 'forbidden',
          kind: CallProblemKind.forbidden,
          retry: false,
          refresh: true,
        ),
        (
          code: 'invalid',
          kind: CallProblemKind.invalid,
          retry: false,
          refresh: false,
        ),
        (
          code: 'not_found',
          kind: CallProblemKind.notFound,
          retry: false,
          refresh: true,
        ),
        (
          code: 'already_resolved',
          kind: CallProblemKind.alreadyResolved,
          retry: false,
          refresh: true,
        ),
        (
          code: 'duplicate',
          kind: CallProblemKind.duplicate,
          retry: false,
          refresh: false,
        ),
        (
          code: 'in_progress',
          kind: CallProblemKind.other,
          retry: false,
          refresh: false,
        ),
        (
          code: 'session_replaced',
          kind: CallProblemKind.other,
          retry: false,
          refresh: false,
        ),
        (
          code: 'session_expired',
          kind: CallProblemKind.other,
          retry: false,
          refresh: false,
        ),
        (
          code: 'bad_request',
          kind: CallProblemKind.other,
          retry: false,
          refresh: false,
        ),
      ];

  for (final row in table) {
    for (final isWrite in [true, false]) {
      test('${row.code} (${isWrite ? 'write' : 'read'}): kind, retry, refresh, '
          'and the server text untouched', () {
        const text = 'Exactly what the server said, “quotes” & 100%.';
        final p = CallProblem.of(
          SocketCallError(row.code, text),
          isWrite: isWrite,
        );
        expect(p.kind, row.kind);
        expect(p.text, text);
        expect(p.canRetry, row.retry);
        expect(p.shouldRefresh, row.refresh);
      });
    }
  }

  test(
    'a connection gap: read = offline (retry); write = unknown outcome (no retry)',
    () {
      for (final code in ['timeout', 'disconnected']) {
        final read = CallProblem.of(SocketCallError(code));
        expect(read.kind, CallProblemKind.offline);
        expect(read.canRetry, isTrue);
        final write = CallProblem.of(SocketCallError(code), isWrite: true);
        expect(write.kind, CallProblemKind.unknownOutcome);
        expect(write.canRetry, isFalse);
        expect(write.shouldRefresh, isTrue);
      }
      final none = CallProblem.of(
        const SocketCallError('not_connected'),
        isWrite: true,
      );
      expect(none.kind, CallProblemKind.offline);
      expect(none.canRetry, isTrue);
    },
  );

  test(
    'the texts of the real refusals in the Postman collection pass through',
    () {
      for (final text in [
        'This ticket was updated by someone else. Reload to see the latest.',
        'You cannot do this on this ticket.',
        'That request has already been answered.',
        'No such notification.',
        'priority must be one of: all, high, medium, low, resolved.',
        'ids must be a non-empty list of notification ids.',
      ]) {
        expect(CallProblem.of(SocketCallError('invalid', text)).text, text);
      }
    },
  );
}
