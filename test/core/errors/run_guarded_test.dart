import 'dart:io';

import 'package:connectum/core/crash/crash_service.dart';
import 'package:connectum/core/errors/app_error.dart';
import 'package:connectum/core/errors/run_guarded.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../crash/fake_crash_reporter.dart';

void main() {
  late FakeCrashReporter reporter;
  late List<String> logs;
  late DebugPrintCallback oldPrint;
  late CrashService oldService;

  setUp(() {
    oldService = CrashService.current;
    reporter = FakeCrashReporter();
    CrashService.current = CrashService(reporter);
    logs = [];
    oldPrint = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() {
    debugPrint = oldPrint;
    CrashService.current = oldService;
  });

  test('unexpected error: reported once, logged, not rethrown', () async {
    AppError? seen;
    runGuarded(
      () async => throw StateError('boom'),
      reason: 'flush outbox',
      onError: (e) => seen = e,
    );
    await Future<void>.delayed(Duration.zero);
    expect(reporter.nonFatals, hasLength(1));
    expect(reporter.reasons.single, 'flush outbox');
    expect(logs, hasLength(1));
    expect(logs.single, contains('flush outbox'));
    expect(seen?.kind, ErrorKind.unknown);
  });

  test('expected network error: not reported, still logged', () async {
    runGuarded(
      () async => throw const SocketException('offline'),
      reason: 'sync',
    );
    await Future<void>.delayed(Duration.zero);
    expect(reporter.nonFatals, isEmpty);
    expect(logs, hasLength(1));
  });

  test('AppError is handed over, not reported', () async {
    AppError? seen;
    runGuarded(
      () async => throw const AppError(ErrorKind.offline, 'x'),
      onError: (e) => seen = e,
    );
    await Future<void>.delayed(Duration.zero);
    expect(seen?.kind, ErrorKind.offline);
    expect(reporter.nonFatals, isEmpty);
  });

  test('secrets in the error are not logged', () async {
    runGuarded(
      () async => throw StateError('token=SECRET123 hello plaintext'),
      reason: 'x',
    );
    await Future<void>.delayed(Duration.zero);
    expect(logs.join(), isNot(contains('SECRET123')));
    expect(logs.join(), isNot(contains('plaintext')));
  });

  test('a throwing onError does not escape', () async {
    runGuarded(
      () async => throw StateError('a'),
      onError: (_) => throw StateError('b'),
    );
    await Future<void>.delayed(Duration.zero);
  });

  test('guarded returns the value or null', () async {
    expect(await guarded(() async => 7), 7);
    expect(await guarded<int>(() async => throw StateError('x')), isNull);
  });

  test('success logs nothing', () async {
    runGuarded(() async {});
    await Future<void>.delayed(Duration.zero);
    expect(logs, isEmpty);
    expect(reporter.nonFatals, isEmpty);
  });
}
