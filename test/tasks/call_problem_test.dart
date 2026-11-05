import 'package:connectum/data/socket/call_problem.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

CallProblem of(String code, [String message = '', bool isWrite = true]) =>
    CallProblem.of(SocketCallError(code, message), isWrite: isWrite);

void main() {
  test('the server text is shown verbatim', () {
    final p = of('rate_limited', 'Too many tasks this hour; try later.');
    expect(p.kind, CallProblemKind.rateLimited);
    expect(p.text, 'Too many tasks this hour; try later.');
    expect(p.canRetry, isTrue);
    expect(p.shouldRefresh, isFalse);
  });

  test('busy: server text, manual retry', () {
    final p = of('busy', 'Too many commands -- slow down and retry.');
    expect(p.kind, CallProblemKind.busy);
    expect(p.text, 'Too many commands -- slow down and retry.');
    expect(p.canRetry, isTrue);
  });

  test('already_resolved: text, refresh, no retry', () {
    final p = of('already_resolved', 'That request has already been answered.');
    expect(p.kind, CallProblemKind.alreadyResolved);
    expect(p.text, 'That request has already been answered.');
    expect(p.shouldRefresh, isTrue);
    expect(p.canRetry, isFalse);
  });

  test('forbidden: text and refresh', () {
    final p = of(
      'forbidden',
      'Only the person who created the task can edit it.',
    );
    expect(p.kind, CallProblemKind.forbidden);
    expect(p.text, 'Only the person who created the task can edit it.');
    expect(p.shouldRefresh, isTrue);
    expect(p.canRetry, isFalse);
  });

  test('not_found: text and refresh (the card is removed)', () {
    final p = of('not_found', 'No such request.');
    expect(p.kind, CallProblemKind.notFound);
    expect(p.text, 'No such request.');
    expect(p.shouldRefresh, isTrue);
  });

  test('invalid: text, no retry', () {
    final p = of(
      'invalid',
      'A finished task cannot be edited; reopen it first.',
    );
    expect(p.kind, CallProblemKind.invalid);
    expect(p.text, 'A finished task cannot be edited; reopen it first.');
    expect(p.canRetry, isFalse);
  });

  test('not connected: nothing was sent, so retry is safe', () {
    final p = of('not_connected');
    expect(p.kind, CallProblemKind.offline);
    expect(p.canRetry, isTrue);
  });

  test('a timeout or drop on a write may have gone through: no retry', () {
    for (final code in ['timeout', 'disconnected']) {
      final p = of(code);
      expect(p.kind, CallProblemKind.unknownOutcome);
      expect(p.canRetry, isFalse);
      expect(p.shouldRefresh, isTrue);
    }
  });

  test('a timeout on a read is just offline', () {
    final p = of('timeout', '', false);
    expect(p.kind, CallProblemKind.offline);
    expect(p.canRetry, isTrue);
  });

  test('an unknown code with no text still says something', () {
    final p = of('weird');
    expect(p.kind, CallProblemKind.other);
    expect(p.text, CallProblem.fallbackText);
  });
}
