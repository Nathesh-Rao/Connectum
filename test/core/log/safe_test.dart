import 'package:connectum/core/log/app_log.dart';
import 'package:connectum/core/log/safe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> lines;
  setUp(() {
    lines = [];
    AppLog.sink = lines.add;
  });
  tearDown(() => AppLog.sink = null);

  test('safeCall returns the value', () async {
    expect(await safeCall('t', () async => 5), 5);
    expect(lines, isEmpty);
  });

  test('safeCall returns fallback and logs on error', () async {
    expect(
      await safeCall<int>('t', () async => throw StateError('x'), fallback: 7),
      7,
    );
    expect(await safeCall<int>('t', () async => throw StateError('x')), isNull);
    expect(lines.length, 2);
    expect(lines.first, contains('[t]'));
  });

  test('safeSync', () {
    expect(safeSync('t', () => 1), 1);
    expect(
      safeSync<int>('t', () => throw const FormatException('s'), fallback: 2),
      2,
    );
    expect(lines.length, 1);
  });

  test('fireAndLog never throws and logs once', () async {
    fireAndLog('t', () async => throw StateError('secret-ish'));
    fireAndLog('ok', () async {});
    await Future<void>.delayed(Duration.zero);
    expect(lines.length, 1);
    expect(lines.single, isNot(contains('secret-ish')));
  });

  test('long messages are truncated', () {
    AppLog.i('t', 'a' * 1000);
    expect(lines.single.length, lessThan(320));
  });
}
