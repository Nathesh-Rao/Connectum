import 'dart:io';

import 'package:connectum/core/log/log_file_sink.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/features/log_viewer/log_viewer_controller.dart';
import 'package:connectum/features/log_viewer/log_viewer_prefs.dart';
import 'package:connectum/features/log_viewer/log_viewer_view.dart';
import 'package:connectum/features/log_viewer/models/log_document.dart';
import 'package:connectum/features/settings/logs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeSink extends LogFileSink {
  _FakeSink(this.file) : super(directory: () async => Directory.systemTemp);

  final File? file;

  @override
  Future<File?> fileForExport() async => file;

  @override
  Future<void> flush() async {}
}

class _FakePrefs extends LogViewerPrefs {
  _FakePrefs() : super(Directory.systemTemp);

  @override
  Future<LogTextSize> loadSize() async => LogTextSize.medium;

  @override
  Future<void> saveSize(LogTextSize size) async {}
}

class _FakeReader extends LogTextReader {
  _FakeReader(this.text, {this.failures = 0});

  final String text;
  int failures;
  int reads = 0;

  @override
  Future<LogDocument> read(File file) async {
    reads++;
    if (failures > 0) {
      failures--;
      throw const FileSystemException('boom');
    }
    return LogDocument.parse(text);
  }

  @override
  Future<LogSearchResult> search(LogDocument doc, String query) async =>
      LogDocument.find(doc.lines, query);
}

const _sample = '''
================================================================================
Connectum Mobile log
Legend: I info | W warning | E error
================================================================================
SESSION START   2026-11-24 10:00:00.000    app 1.0
================================================================================
-- 2026-11-24 ------------------------------------------------------------------
10:00:01.000  I  APP       started
10:00:02.000  W  SOCKET    slow reply
                 detail of the warning
10:00:03.000  E  SESSION   token refused
                 at Foo.bar (foo.dart:1)
10:00:04.000  I  APP       Started again
''';

Future<LogViewerController> _open(
  WidgetTester tester,
  LogTextReader reader, {
  File? file,
  double scale = 1,
  bool isMissing = false,
}) async {
  Get.testMode = true;
  final f =
      file ?? File('${Directory.systemTemp.path}/ConnectumMobileLog_x.txt');
  final sink = _FakeSink(isMissing ? null : f);
  final c = LogViewerController(
    sink: sink,
    logs: LogsController(sink: sink),
    reader: reader,
    prefs: _FakePrefs(),
    searchDelay: Duration.zero,
  );
  Get.put(c);
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(Get.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: AppNoticeHost(child: const LogViewerView()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return c;
}

Color? _bgOf(WidgetTester tester, String text) {
  final box = find
      .ancestor(
        of: find.textContaining(text, findRichText: true),
        matching: find.byType(Container),
      )
      .first;
  return (tester.widget<Container>(box).color);
}

void main() {
  test('parse classifies header, separators, levels and continuations', () {
    final d = LogDocument.parse(_sample);
    LogLineKind k(String start) =>
        d.kindOf(d.lines.indexWhere((l) => l.startsWith(start)));
    expect(d.kindOf(1), LogLineKind.muted);
    expect(k('SESSION START'), LogLineKind.muted);
    expect(k('-- 2026'), LogLineKind.muted);
    expect(k('10:00:01'), LogLineKind.normal);
    expect(k('10:00:02'), LogLineKind.warning);
    expect(k('10:00:03'), LogLineKind.error);
    expect(
      d.kindOf(d.lines.indexWhere((l) => l.contains('at Foo.bar'))),
      LogLineKind.error,
    );
    expect(k('10:00:04'), LogLineKind.normal);
  });

  test('find is case-insensitive and capped', () {
    final r = LogDocument.find([
      'Started',
      'no',
      'a started b started',
    ], 'STARTED');
    expect(r.hits.map((h) => '${h.line}:${h.start}'), ['0:0', '2:2', '2:12']);
    final big = LogDocument.find(List.filled(6000, 'x'), 'x');
    expect(big.hits.length, LogDocument.maxHits);
    expect(big.isCut, isTrue);
  });

  test('row index cuts long lines and maps rows back', () {
    final d = LogDocument.parse('abcdefghij\nxy\n\nklm');
    final r = LogRowIndex(d, 4);
    expect(r.rowCount, 3 + 1 + 1 + 1);
    expect(
      [for (var i = 0; i < r.rowCount; i++) r.lineOf(i)],
      [0, 0, 0, 1, 2, 3],
    );
    expect(r.rangeOf(2, 0), (8, 10));
    expect(r.rowOf(0, 9), 2);
    expect(LogRowIndex(d, 0).rowCount, 4);
  });

  testWidgets('lines render, E and W are tinted, I is not', (tester) async {
    await _open(tester, _FakeReader(_sample));
    expect(
      find.textContaining('token refused', findRichText: true),
      findsOneWidget,
    );
    expect(
      _bgOf(tester, 'token refused'),
      AppColors.error.withValues(alpha: 0.08),
    );
    expect(_bgOf(tester, 'slow reply'), AppColors.violetTint);
    expect(_bgOf(tester, 'started again'.replaceFirst('s', 'S')), isNull);
  });

  testWidgets('opens at the end; jump buttons move to the top and back', (
    tester,
  ) async {
    final text = [
      for (var i = 0; i < 400; i++) '10:00:00.000  I  APP       line $i',
    ].join('\n');
    final c = await _open(tester, _FakeReader(text));
    await tester.pump();
    await tester.pump();
    expect(c.scroll.position.extentAfter, lessThan(2));
    expect(find.textContaining('line 399', findRichText: true), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('log-jump-top')));
    await tester.pump();
    await tester.pump();
    expect(c.scroll.position.pixels, 0);
    expect(find.textContaining('line 0', findRichText: true), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('log-jump-latest')));
    await tester.pump();
    await tester.pump();
    expect(c.scroll.position.extentAfter, lessThan(2));
  });

  testWidgets('wrap toggle switches to fixed lines scrolled sideways', (
    tester,
  ) async {
    final long = '10:00:00.000  I  APP       ${'word ' * 80}';
    final c = await _open(tester, _FakeReader(long));
    expect(c.isWrap.value, isTrue);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.tap(find.byKey(const ValueKey('log-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrap lines'));
    await tester.pumpAndSettle();
    expect(c.isWrap.value, isFalse);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('a partial document shows the note', (tester) async {
    final c = await _open(tester, _FakeReader(_sample));
    expect(find.byKey(const ValueKey('log-partial')), findsNothing);
    c.doc.value = LogDocument(
      c.doc.value.lines,
      c.doc.value.kinds,
      c.doc.value.longest,
      isPartial: true,
    );
    await tester.pump();
    expect(find.text('Showing last part of file'), findsOneWidget);
  });

  testWidgets('empty file shows the empty state', (tester) async {
    await _open(tester, _FakeReader(''));
    expect(find.text('No log entries yet'), findsOneWidget);
  });

  testWidgets('a missing file shows the empty state', (tester) async {
    await _open(tester, _FakeReader(_sample), isMissing: true);
    expect(find.text('No log entries yet'), findsOneWidget);
    expect(find.text('Could not load'), findsNothing);
  });

  test('a file over 2 MB is read from the end and marked partial', () async {
    final dir = await Directory.systemTemp.createTemp('logtail');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/big.txt');
    final line = '10:00:01.000  I  APP       ${'x' * 90}\n';
    final count = (3 * 1024 * 1024) ~/ line.length;
    await f.writeAsString('FIRST LINE\n${line * count}LAST LINE\n');
    final doc = await LogDocument.readFile(f.path);
    expect(doc.isPartial, isTrue);
    expect(doc.lines.first, isNot('FIRST LINE'));
    expect(doc.lines.last, 'LAST LINE');
    final small = File('${dir.path}/small.txt')..writeAsStringSync('a\nb\n');
    expect((await LogDocument.readFile(small.path)).isPartial, isFalse);
  });

  testWidgets('a failed read shows the error state and Retry reads again', (
    tester,
  ) async {
    final reader = _FakeReader(_sample, failures: 1);
    await _open(tester, reader);
    expect(find.text('Could not load'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(reader.reads, 2);
    expect(
      find.textContaining('token refused', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('search counts matches and steps through them', (tester) async {
    final c = await _open(tester, _FakeReader(_sample));
    await tester.tap(find.byKey(const ValueKey('log-search')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'started');
    await tester.pump();
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
    c.nextHit();
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('text scale 1.3 does not overflow', (tester) async {
    await _open(tester, _FakeReader(_sample), scale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 50,000 line file builds only the visible rows', (
    tester,
  ) async {
    final text = [
      for (var i = 0; i < 50000; i++) '10:00:00.000  I  APP       line $i',
    ].join('\n');
    await _open(tester, _FakeReader(text));
    final rows = find.byKey(const ValueKey('log-lines'));
    expect(rows, findsOneWidget);
    final built = find.descendant(
      of: rows,
      matching: find.byType(Text, skipOffstage: false),
    );
    expect(built.evaluate().length, lessThan(100));
    expect(built.evaluate().length, greaterThan(5));
  });
}
