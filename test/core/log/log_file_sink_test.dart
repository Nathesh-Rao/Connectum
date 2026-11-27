import 'dart:io';

import 'package:connectum/core/log/log_file_sink.dart';
import 'package:connectum/core/log/log_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late LogContext ctx;
  final sinks = <LogFileSink>[];

  LogFileSink make({int maxBytes = 10 * 1024 * 1024}) {
    final s = LogFileSink(
      directory: () async => dir,
      clock: () => now,
      context: () => ctx,
      environment: () async =>
          const LogEnvironment(version: '1.0.0 (1)', device: 'Test, OS 1'),
      maxBytes: maxBytes,
      flushInterval: const Duration(hours: 1),
    );
    sinks.add(s);
    return s;
  }

  List<File> files() => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('ConnectumMobileLog_'))
      .toList();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('logtest');
    now = DateTime(2026, 11, 23, 10, 0, 0);
    ctx = LogContext.unknown;
  });

  tearDown(() async {
    for (final s in sinks) {
      await s.flush();
    }
    sinks.clear();
    await dir.delete(recursive: true);
  });

  test('no file before enabling, nothing written while off', () async {
    final s = make();
    await s.init();
    s.log('E', 't', 'boom');
    await s.flush();
    expect(files(), isEmpty);
    expect(s.isEnabled, isFalse);
  });

  test('first enable creates a timestamped file with the header', () async {
    final s = make();
    await s.init();
    expect(await s.hasOldFile(), isFalse);
    await s.startNew();
    final f = files().single;
    expect(f.path, endsWith('ConnectumMobileLog_20261123_100000.txt'));
    final text = await f.readAsString();
    expect(text, contains('App name:     Connectum Mobile'));
    expect(text, contains('Device:       Test, OS 1'));
    expect(text, contains('=' * 80));
    expect(s.state.value.isEnabled, isTrue);
  });

  test('entries are written with caller and level', () async {
    final s = make();
    await s.init();
    await s.startNew();
    s.log('I', 'tag', 'hello');
    s.log(
      'E',
      'tag',
      'bad',
      stack: StackTrace.fromString('#0 f (package:connectum/a.dart:1:1)'),
    );
    await s.flush();
    final text = await files().single.readAsString();
    expect(text, contains('  I  TAG       hello'));
    expect(text, contains('  E  TAG       bad'));
    expect(text, contains('${' ' * 27}#0 f (package:connectum/a.dart:1:1)'));
    expect(text, contains('SESSION START   2026-11-23 10:00:00.000'));
    expect(text, contains('-- 2026-11-23 ${'-' * 66}'));
  });

  test('identical consecutive entries collapse', () async {
    final s = make();
    await s.init();
    await s.startNew();
    for (var i = 0; i < 4; i++) {
      s.log(
        'E',
        't',
        'same',
        stack: StackTrace.fromString('#0 f (package:connectum/a.dart:1:1)'),
      );
    }
    s.log('I', 't', 'other');
    await s.flush();
    final text = await files().single.readAsString();
    expect(text, contains('same  (x4)'));
    expect('same'.allMatches(text).length, 1);
    s.log('I', 't', 'once');
    s.log('I', 't', 'next');
    await s.flush();
    final again = await files().single.readAsString();
    expect(again, contains('once\n'));
    expect(again, isNot(contains('(x1)')));
  });

  test('off writes the closing line and keeps the file', () async {
    final s = make();
    await s.init();
    await s.startNew();
    await s.disable();
    s.log('I', 't', 'after');
    await s.flush();
    final text = await files().single.readAsString();
    expect(text.trimRight().split('\n').last, contains('LOGGING DISABLED'));
    expect(text, isNot(contains('after')));
    expect(s.isEnabled, isFalse);
    expect(s.state.value.fileName, isNotNull);
  });

  test('on again, Yes deletes the old file and creates a new one', () async {
    final s = make();
    await s.init();
    await s.startNew();
    await s.disable();
    expect(await s.hasOldFile(), isTrue);
    now = now.add(const Duration(minutes: 5));
    await s.startNew();
    final f = files().single;
    expect(f.path, endsWith('ConnectumMobileLog_20261123_100500.txt'));
  });

  test('on again, No keeps the file and adds a new header', () async {
    final s = make();
    await s.init();
    await s.startNew();
    s.log('I', 't', 'first');
    await s.disable();
    now = now.add(const Duration(minutes: 5));
    ctx = const LogContext(user: 'A <a@b.c>', org: 'Acme', isKnown: true);
    await s.startAppend();
    s.log('I', 't', 'second');
    await s.flush();
    final text = await files().single.readAsString();
    expect('App name:'.allMatches(text).length, 2);
    expect(text, contains('first'));
    expect(text, contains('second'));
    expect(text, contains('User:         A <a@b.c>'));
    expect(text, contains('new session'));
  });

  test('a dismissed dialog leaves it off (nothing is started)', () async {
    final s = make();
    await s.init();
    await s.startNew();
    await s.disable();
    expect(await s.hasOldFile(), isTrue);
    expect(s.isEnabled, isFalse);
    s.log('I', 't', 'x');
    await s.flush();
    expect(files(), hasLength(1));
  });

  test('a file deleted externally gives a new file', () async {
    final s = make();
    await s.init();
    await s.startNew();
    await s.disable();
    files().single.deleteSync();
    expect(await s.hasOldFile(), isFalse);
    now = now.add(const Duration(minutes: 1));
    await s.startNew();
    expect(files().single.path, endsWith('100100.txt'));
  });

  test('restart with the switch on appends under a session marker', () async {
    final a = make();
    await a.init();
    await a.startNew();
    a.log('I', 't', 'before');
    await a.flush();
    final b = make();
    now = now.add(const Duration(minutes: 1));
    await b.init();
    b.log('I', 't', 'after');
    await b.flush();
    final text = await files().single.readAsString();
    expect(
      text,
      contains('SESSION START   2026-11-23 10:01:00.000    app 1.0.0 (1)'),
    );
    expect('App name:'.allMatches(text).length, 1);
    expect(text, contains('before'));
    expect(text, contains('after'));
  });

  test('restart with the file missing creates a new one', () async {
    final a = make();
    await a.init();
    await a.startNew();
    files().single.deleteSync();
    now = now.add(const Duration(minutes: 1));
    final b = make();
    await b.init();
    expect(files().single.path, endsWith('100100.txt'));
  });

  test('size cap writes one line and stops', () async {
    final s = make(maxBytes: 1200);
    await s.init();
    await s.startNew();
    for (var i = 0; i < 50; i++) {
      s.log('I', 't', 'line $i ${'x' * 40}');
    }
    await s.flush();
    final text = await files().single.readAsString();
    expect('LOG SIZE LIMIT REACHED'.allMatches(text).length, 1);
    expect(text, isNot(contains('line 49')));
    expect(files().single.lengthSync(), lessThan(1500));
  });

  test('the date line is written again when the day changes', () async {
    final s = make();
    await s.init();
    await s.startNew();
    s.log('I', 't', 'today');
    now = DateTime(2026, 11, 24, 0, 0, 1);
    s.log('I', 't', 'tomorrow');
    await s.flush();
    final text = await files().single.readAsString();
    expect('-- 2026-11-23 '.allMatches(text).length, 1);
    expect('-- 2026-11-24 '.allMatches(text).length, 1);
  });

  test('a context change writes one SESSION line', () async {
    final s = make();
    await s.init();
    await s.startNew();
    ctx = const LogContext(user: 'A <a@b.c>', org: 'Acme', isKnown: true);
    s.updateContext();
    s.updateContext();
    await s.flush();
    final text = await files().single.readAsString();
    expect('SESSION   user=A <a@b.c>  org=Acme'.allMatches(text).length, 1);
  });

  test('logger failures never throw', () async {
    final s = LogFileSink(
      directory: () async => throw const FileSystemException('nope'),
    );
    await s.init();
    await s.startNew();
    await s.startAppend();
    s.log('E', 't', 'x');
    s.updateContext();
    await s.flush();
    await s.disable();
    expect(await s.fileForExport(), isNull);
  });
}
