import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/data/smart_view/preview/sv_preview_parsers.dart';
import 'package:connectum/data/smart_view/preview/sv_xlsx_parser.dart';
import 'package:connectum/data/smart_view/sv_file.dart';
import 'package:connectum/features/smart_view/sv_file_preview_controller.dart';
import 'package:connectum/features/smart_view/viewers/sv_sheet_viewer.dart';
import 'package:connectum/features/smart_view/viewers/sv_viewers.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_preview_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

const _ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, text) {
    final data = utf8.encode(text);
    a.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

String _workbook(List<String> names, {String extra = ''}) =>
    '<workbook $_ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">$extra<sheets>'
    '${[for (var i = 0; i < names.length; i++) '<sheet name="${names[i]}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
    '</sheets></workbook>';

String _rels(int n) =>
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${[for (var i = 0; i < n; i++) '<Relationship Id="rId${i + 1}" Type="x" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
    '</Relationships>';

const _styles =
    '<styleSheet $_ns><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd\\ hh:mm"/></numFmts>'
    '<cellStyleXfs count="1"><xf numFmtId="14"/></cellStyleXfs>'
    '<cellXfs count="5"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="10"/>'
    '<xf numFmtId="164"/><xf numFmtId="4"/></cellXfs></styleSheet>';

/// Sheet1: text, number, date, boolean, empty, formula, percent, money.
Uint8List _book() => _zip({
  'xl/workbook.xml': _workbook(['Sheet1', 'Totals']),
  'xl/_rels/workbook.xml.rels': _rels(2),
  'xl/sharedStrings.xml':
      '<sst $_ns><si><t>Name</t></si><si><r><t>R&amp;D </t></r><r><t>team</t></r></si>'
      '<si><t>Amount</t><rPh><t>ignored</t></rPh></si></sst>',
  'xl/styles.xml': _styles,
  'xl/worksheets/sheet1.xml':
      '<worksheet $_ns><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>2</v></c><c r="C1" t="inlineStr"><is><t>Inline</t></is></c></row>'
      '<row r="2"><c r="A2" t="s"><v>1</v></c><c r="B2"><v>0.30000000000000004</v></c>'
      '<c r="D2" s="1"><v>46023</v></c><c r="E2" t="b"><v>1</v></c></row>'
      '<row r="4"><c r="A4"><v>3</v></c><c r="B4"><f>SUM(A4:A4)+1</f><v>4</v></c>'
      '<c r="C4" s="2"><v>0.256</v></c><c r="D4" s="3"><v>46023.5</v></c>'
      '<c r="E4" s="4"><v>1234567.5</v></c><c r="F4" t="e"><v>#DIV/0!</v></c>'
      '<c r="G4" t="str"><f>A1</f><v>Name</v></c></row>'
      '</sheetData></worksheet>',
  'xl/worksheets/sheet2.xml':
      '<worksheet $_ns><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Only</t></is></c></row></sheetData></worksheet>',
});

Uint8List _wide(int rows, int cols) {
  final sb = StringBuffer('<worksheet $_ns><sheetData>');
  for (var r = 1; r <= rows; r++) {
    sb.write('<row r="$r">');
    for (var c = 0; c < cols; c++) {
      sb.write(
        '<c r="${SvSheetViewer.letters(c)}$r"><v>${r * 1000 + c}</v></c>',
      );
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');
  return _zip({
    'xl/workbook.xml': _workbook(['Sheet1']),
    'xl/_rels/workbook.xml.rels': _rels(1),
    'xl/worksheets/sheet1.xml': sb.toString(),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parser', () {
    test('sheets, shared strings, numbers, date, boolean, empty cell', () {
      final book = SvXlsxParser.parse(_book())!;
      expect(book.tables.map((t) => t.name), ['Sheet1', 'Totals']);
      final rows = book.tables.first.rows;
      expect(rows[0], ['Name', 'Amount', 'Inline']);
      expect(rows[1][0], 'R&D team');
      expect(rows[1][1], '0.3');
      expect(rows[1][2], '');
      expect(rows[1][3], '2026-01-01');
      expect(rows[1][4], 'TRUE');
      expect(rows[2], isEmpty);
      expect(rows[3][0], '3');
      expect(rows[3][1], '4', reason: 'the cached formula result');
      expect(rows[3][2], '25.60%');
      expect(rows[3][3], '2026-01-01 12:00');
      expect(rows[3][4], '1,234,567.50');
      expect(rows[3][5], '#DIV/0!');
      expect(rows[3][6], 'Name');
      expect(book.tables.last.rows.single, ['Only']);
      expect(book.tables.first.isCut, isFalse);
    });

    test('truncates to 200 rows and 30 columns', () {
      final t = SvXlsxParser.parse(_wide(250, 35))!.tables.single;
      expect(t.rows, hasLength(200));
      expect(t.columns, 30);
      expect(t.isCut, isTrue);
      expect(t.rows.last.last, '${200 * 1000 + 29}');
    });

    test('a hidden sheet is left out', () {
      final z = _zip({
        'xl/workbook.xml':
            '<workbook $_ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
            '<sheet name="A" sheetId="1" r:id="rId1"/><sheet name="B" sheetId="2" state="hidden" r:id="rId2"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels': _rels(2),
        'xl/worksheets/sheet1.xml':
            '<worksheet $_ns><sheetData><row r="1"><c r="A1"><v>1</v></c></row></sheetData></worksheet>',
        'xl/worksheets/sheet2.xml': '<worksheet $_ns><sheetData/></worksheet>',
      });
      expect(SvXlsxParser.parse(z)!.tables.map((t) => t.name), ['A']);
    });

    test('over 5 MB gives null', () {
      expect(SvXlsxParser.parse(Uint8List(6 * 1024 * 1024)), isNull);
    });

    test('over 20 MB unzipped gives null (zip bomb)', () {
      final big = Uint8List(21 * 1024 * 1024);
      final a = Archive()
        ..addFile(ArchiveFile('xl/workbook.xml', big.length, big));
      final z = Uint8List.fromList(ZipEncoder().encode(a));
      expect(z.length, lessThan(SvXlsxParser.maxFileBytes));
      expect(SvXlsxParser.parse(z), isNull);
    });

    test('an unusual entry count gives null', () {
      final a = Archive();
      for (var i = 0; i < 2100; i++) {
        a.addFile(ArchiveFile('f$i.txt', 1, [65]));
      }
      expect(
        SvXlsxParser.parse(Uint8List.fromList(ZipEncoder().encode(a))),
        isNull,
      );
    });

    test('corrupt, truncated, empty and missing parts give null', () {
      expect(SvXlsxParser.parse(Uint8List.fromList([1, 2, 3, 4])), isNull);
      final good = _book();
      expect(SvXlsxParser.parse(good.sublist(0, good.length ~/ 2)), isNull);
      expect(SvXlsxParser.parse(Uint8List(0)), isNull);
      expect(SvXlsxParser.parse(_zip({'readme.txt': 'hi'})), isNull);
      expect(
        SvXlsxParser.parse(
          _zip({'xl/workbook.xml': '<workbook><sheets><sheet'}),
        ),
        isNull,
      );
    });
  });

  group('viewer', () {
    SvSheetBook book() => SvXlsxParser.parse(_book())!;

    Future<void> pump(
      WidgetTester t,
      SvSheetBook b, {
      double width = 390,
      double scale = 1,
    }) async {
      t.view.physicalSize = Size(width, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: SvSheetViewer(book: b)),
        ),
      );
      await t.pump();
    }

    testWidgets('column letters, row numbers, tabs and sheet switching', (
      t,
    ) async {
      await pump(t, book());
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('R&D team'), findsOneWidget);
      expect(find.byKey(const ValueKey('sv-sheet-tabs')), findsOneWidget);
      await t.tap(find.text('Totals'));
      await t.pump();
      expect(find.text('Only'), findsOneWidget);
      expect(find.text('R&D team'), findsNothing);
    });

    testWidgets('the footer note names the cut', (t) async {
      await pump(t, SvXlsxParser.parse(_wide(250, 35))!);
      expect(
        find.text("Showing the first 200 rows and 30 columns of 'Sheet1'"),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sv-sheet-tabs')), findsNothing);
    });

    testWidgets('an empty sheet says so', (t) async {
      await pump(t, const SvSheetBook([SvSheetTable(name: 'E', rows: [])]));
      expect(find.byKey(const ValueKey('sv-sheet-empty')), findsOneWidget);
    });

    testWidgets('fits 320 px at 1.5x text', (t) async {
      await pump(t, book(), width: 320, scale: 1.5);
      expect(t.takeException(), isNull);
      expect(find.text('Sheet1'), findsOneWidget);
      expect(find.text('Totals'), findsOneWidget);
    });

    test('column letters run past Z', () {
      expect(SvSheetViewer.letters(0), 'A');
      expect(SvSheetViewer.letters(25), 'Z');
      expect(SvSheetViewer.letters(26), 'AA');
      expect(SvSheetViewer.letters(701), 'ZZ');
      expect(SvSheetViewer.letters(702), 'AAA');
    });
  });

  group('preview', () {
    late Directory temp;
    late SvFileRepository repo;
    Uint8List bytes = Uint8List(0);

    setUp(() {
      temp = Directory.systemTemp.createTempSync('svx_temp');
      repo = SvFileRepository(
        dio: Dio(),
        token: () => null,
        origin: '',
        cache: AttachmentCache(Dio()),
        onUnauthorized: () {},
        store: FakeStore(),
        fetcher: (f, path, etag, onProgress, cancel) async {
          await File(path).writeAsBytes(bytes);
          return const SvFileReply(200);
        },
        tempDir: () async => temp..createSync(recursive: true),
        saver: (name, file, mime) async => null,
      );
    });

    tearDown(() {
      repo.dispose();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final file = SvFile(id: 'c' * 24, name: 'plan.xlsx', size: 1000);

    test('an xlsx has the sheet viewer', () {
      expect(file.viewer, SvViewer.sheet);
    });

    Future<SvFilePreviewController> open(WidgetTester t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = SvFilePreviewController(files: [file], repo: repo);
      await t.runAsync(() => c.ensure(c.loads.first));
      await t.pumpWidget(
        MaterialApp(
          home: SvFilePreviewBody(controller: c, viewers: const SvViewers()),
        ),
      );
      await t.pump(const Duration(milliseconds: 200));
      return c;
    }

    testWidgets('a good file shows the table', (t) async {
      bytes = _book();
      final c = await open(t);
      expect(c.loads.first.isShowable.value, isTrue);
      expect(find.byType(SvSheetViewer), findsOneWidget);
      expect(find.text('R&D team'), findsOneWidget);
      expect(c.loads.first.isParsing.value, isFalse);
    });

    testWidgets('a corrupt file falls back to the card, no spinner', (t) async {
      bytes = Uint8List.fromList(List.filled(300, 7));
      final c = await open(t);
      expect(c.loads.first.isShowable.value, isFalse);
      expect(c.loads.first.isParsing.value, isFalse);
      expect(find.byType(SvSheetViewer), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a file over 5 MB is not loaded for preview', (t) async {
      final big = SvFile(id: 'd' * 24, name: 'big.xlsx', size: 6 * 1024 * 1024);
      final c = SvFilePreviewController(files: [big], repo: repo);
      c.onPage(0);
      expect(c.loads.first.phase.value, SvFilePhase.idle);
    });

    testWidgets('a skeleton shows while it is parsing', (t) async {
      bytes = _book();
      final c = SvFilePreviewController(files: [file], repo: repo);
      c.loads.first.phase.value = SvFilePhase.loading;
      c.loads.first.isParsing.value = true;
      await t.pumpWidget(
        MaterialApp(
          home: SvFilePreviewBody(controller: c, viewers: const SvViewers()),
        ),
      );
      await t.pump();
      expect(find.byKey(const ValueKey('sv-sheet-skeleton')), findsOneWidget);
    });
  });

  test('csv still parses into the same table type', () {
    final t = SvPreviewParsers.parseCsv('a,b\n1,2\n');
    expect(t.rows, hasLength(2));
  });
}
