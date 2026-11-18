import 'dart:io';

import 'package:connectum/core/debug/seed_smart_files.dart';
import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/data/smart_view/sv_file.dart';
import 'package:connectum/features/smart_view/sv_file_preview_controller.dart';
import 'package:connectum/features/smart_view/widgets/smart_view_table.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_chips.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_preview_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

// Fakes only: a fake downloader, temp folders, no server, no phone (DevGuard
// is for the integration tests).

final _png = SeedSmartFiles.files[0];
final _text = SeedSmartFiles.files[1];
final _bigText = SeedSmartFiles.files[2];
final _pdf = SeedSmartFiles.files[3];
final _long = SeedSmartFiles.files[4];
final _zip = SeedSmartFiles.files[5];
final _fail = SeedSmartFiles.files[6];

Future<void> _fast(
  SvFile f,
  String path,
  void Function(double) onProgress,
  CancelToken cancel,
) => SeedSmartFiles.fetch(f, path, onProgress, cancel, step: Duration.zero);

class _Rig {
  _Rig({SvFileFetcher? fetcher, int limit = 100 * 1024 * 1024}) {
    temp = Directory.systemTemp.createTempSync('svf_temp');
    repo = SvFileRepository(
      dio: Dio(),
      token: () => null,
      origin: '',
      cache: AttachmentCache(Dio()),
      onUnauthorized: () => unauthorized++,
      store: store,
      fetcher: fetcher ?? _fast,
      cacheLimit: limit,
      tempDir: () async => temp..createSync(recursive: true),
      saver: (name, bytes, mime) async {
        asked.add((name: name, bytes: bytes.length, mime: mime));
        final out = onSave?.call(name);
        return out;
      },
    );
  }

  final store = FakeStore();
  late final Directory temp;
  final asked = <({String name, int bytes, String mime})>[];

  /// What the fake save dialog answers: a place, null (cancel) or an error.
  Uri? Function(String name)? onSave;
  late final SvFileRepository repo;
  int unauthorized = 0;

  SvFilePreviewController preview(List<SvFile> files, [int index = 0]) =>
      SvFilePreviewController(files: files, repo: repo, index: index);

  void dispose() {
    repo.dispose();
    for (final d in [temp]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  }
}

SvSource _source() => const SvSource(
  name: 's',
  caption: 'S',
  keyField: 'title',
  fields: [
    SvField(name: 'title', caption: 'Title'),
    SvField(name: 'doc', caption: 'Documents', type: 'file'),
  ],
);

Map<String, dynamic> _info(List<SvFile> files) => {
  'doc': [
    for (final f in files)
      {'id': f.id, 'name': f.name, 'mime': f.mime, 'size': f.size},
  ],
};

SvRow _row(int id, List<SvFile> files, {Map<String, dynamic>? extra}) => SvRow(
  id: id,
  tstruct: 's',
  by: 'me',
  ts: DateTime(2026, 11, 18, 12).millisecondsSinceEpoch,
  values: {
    'title': 'Row $id',
    'doc': [for (final f in files) f.id],
    ...?extra,
  },
  files: _info(files),
);

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    backgroundColor: Colors.white,
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

Future<void> _size(
  WidgetTester tester, [
  Size size = const Size(360, 640),
]) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpFor(WidgetTester tester, [int ms = 300]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('file kinds and names', () {
    test('kind comes from mime, then extension; SVG is never an image', () {
      SvFileKind k(String n, [String m = '']) => SvFile.kindOf(n, m);
      expect(k('a', 'image/png'), SvFileKind.image);
      expect(k('a.JPG'), SvFileKind.image);
      expect(k('a.svg', 'image/svg+xml'), SvFileKind.other);
      expect(k('a', 'application/pdf'), SvFileKind.pdf);
      expect(k('a.pdf'), SvFileKind.pdf);
      expect(k('a.mp4'), SvFileKind.video);
      expect(k('a', 'audio/mpeg'), SvFileKind.audio);
      expect(k('a.csv'), SvFileKind.text);
      expect(k('a', 'application/json'), SvFileKind.text);
      expect(k('a.log'), SvFileKind.text);
      expect(
        k(
          'a',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        SvFileKind.office,
      );
      expect(k('a.xlsx'), SvFileKind.office);
      expect(k('a.zip', 'application/zip'), SvFileKind.archive);
      expect(k('a.7z'), SvFileKind.archive);
      expect(k('a.bin'), SvFileKind.other);
      expect(k(''), SvFileKind.other);
    });

    test('names are cleaned, de-duplicated and cut in the middle', () {
      expect(SvFile.sanitizeName('../../etc/passwd'), 'passwd');
      expect(SvFile.sanitizeName(r'C:\x\y\report.pdf'), 'report.pdf');
      expect(SvFile.sanitizeName('a\u0000b:c*.txt'), 'a_b_c_.txt');
      expect(SvFile.sanitizeName('...'), 'file');
      expect(SvFile.sanitizeName('.hidden'), 'hidden');
      expect(SvFile.sanitizeName('${'x' * 300}.pdf').length, 100);
      expect(SvFile.sanitizeName('${'x' * 300}.pdf').endsWith('.pdf'), isTrue);
      final m = SvFile.middleEllipsis('${'a' * 50}.pdf', 26);
      expect(m.length, 26);
      expect(m.endsWith('.pdf'), isTrue);
      expect(m.contains('…'), isTrue);
      expect(SvFile.formatSize(0), '');
      expect(SvFile.formatSize(2048), '2 KB');
      expect(SvFile.formatSize(1572864), '1.5 MB');
    });

    test('only 24-hex ids are files; duplicates and a 21st are dropped', () {
      final list = SvFile.listOf(
        [
          'a00000000000000000000001',
          'a00000000000000000000001',
          'not-an-id',
          'javascript:alert(1)',
          'a00000000000000000000002',
        ],
        [
          {
            'id': 'a00000000000000000000001',
            'name': 'x.png',
            'mime': 'image/png',
            'size': 5,
          },
        ],
      );
      expect([for (final f in list) f.name], ['x.png', 'File']);
      final many = SvFile.listOf([
        for (var i = 0; i < 30; i++) 'b${i.toString().padLeft(23, '0')}',
      ], null);
      expect(many.length, 20);
    });

    test('image bytes are sniffed, SVG and text are not images', () {
      expect(
        SvFileRepository.isImageHead([0x89, 0x50, 0x4E, 0x47, 0x0D]),
        isTrue,
      );
      expect(SvFileRepository.isImageHead([0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
      expect(SvFileRepository.isImageHead('<svg xmlns'.codeUnits), isFalse);
      expect(SvFileRepository.isImageHead('%PDF-1.4'.codeUnits), isFalse);
      expect(SvFileRepository.isImageHead(const []), isFalse);
    });
  });

  group('file values in the columns', () {
    test('a file field gives typed files; hidden fields never do', () {
      final cols = SmartViewColumns.of(_source());
      final row = _row(
        1,
        [_png, _pdf],
        extra: {
          'secret_docs': [SeedSmartFiles.hiddenId],
        },
      );
      final doc = cols.columns.firstWhere((c) => c.key == 'doc');
      final cell = cols.cellOf(doc, row);
      expect(cell.files.map((f) => f.name), [
        'site-photo.png',
        'Medical certificate.pdf',
      ]);
      expect(cell.files.first.kind, SvFileKind.image);
      expect(cell.files.last.kind, SvFileKind.pdf);
      expect(cols.columns.any((c) => c.key == 'secret_docs'), isFalse);
      for (final c in cols.cellsOf(row)) {
        expect(c.files.any((f) => f.id == SeedSmartFiles.hiddenId), isFalse);
      }
    });

    test('no files is a dash', () {
      final cols = SmartViewColumns.of(_source());
      final doc = cols.columns.firstWhere((c) => c.key == 'doc');
      final cell = cols.cellOf(doc, _row(2, const []));
      expect(cell.files, isEmpty);
      expect(cell.isEmpty, isTrue);
    });

    test(
      'the demo hides internal files: they are in the rows, in no column',
      () {
        final values = {
          'attach': [SeedSmartFiles.imageId],
          'internal_files': [SeedSmartFiles.hiddenId],
        };
        expect(
          SeedSmartFiles.infoOf(values).keys,
          containsAll(['attach', 'internal_files']),
        );
      },
    );
  });

  group('chips', () {
    final five = [_png, _text, _pdf, _long, _zip];

    testWidgets('three chips then "+2 more"; a tap opens at that file', (
      tester,
    ) async {
      await _size(tester);
      final opened = <(int, int)>[];
      await tester.pumpWidget(
        _host(
          SvFileChips(
            files: five,
            onOpen: (f, i) => opened.add((f.length, i)),
            onToggle: () {},
          ),
        ),
      );
      expect(find.byType(SvFileTile), findsNWidgets(3));
      expect(find.text('+2 more'), findsOneWidget);
      for (final chip in tester.widgetList<SvFileTile>(
        find.byType(SvFileTile),
      )) {
        expect(chip.file.name.isNotEmpty, isTrue);
      }
      for (final e in tester.elementList(find.byType(SvFileTile))) {
        expect(e.size!.height, greaterThanOrEqualTo(44));
      }
      await tester.tap(find.byType(SvFileTile).at(1));
      await tester.tap(find.text('+2 more'));
      expect(opened, [(5, 1)]);
      expect(find.bySemanticsLabel('File notes.txt, 1 KB'), findsOneWidget);
    });

    testWidgets('a long name is cut in the middle with the extension kept', (
      tester,
    ) async {
      await _size(tester);
      await tester.pumpWidget(_host(SvFileChips(files: [_long])));
      final text = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(SvFileTile),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(text.data!.endsWith('.xlsx'), isTrue);
      expect(text.data!.contains('…'), isTrue);
      expect(text.maxLines, 1);
    });

    testWidgets('golden: sv_file_chips', (tester) async {
      await _size(tester, const Size(360, 420));
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SvFileChips(files: five, onOpen: (_, _) {}, onToggle: () {}),
                const SizedBox(height: 12),
                SvFileChips(files: [_png, _fail], onOpen: (_, _) {}),
              ],
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_chips.png'),
      );
    });
  });

  group('table', () {
    testWidgets('one chip and "+N" on a single line; golden: sv_table_files', (
      tester,
    ) async {
      await _size(tester);
      final opened = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SmartViewTable(
              source: _source(),
              rows: [
                _row(1, [_png, _text, _pdf]),
                _row(2, [_long]),
                _row(3, const []),
              ],
              versions: const {},
              onRefresh: () async {},
              footer: const SizedBox.shrink(),
              onOpenFiles: (f, i) => opened.add(i),
            ),
          ),
        ),
      );
      await _pumpFor(tester);
      expect(find.byType(SvFileTableCell), findsNWidgets(2));
      expect(find.byType(SvFileChip), findsNWidgets(2));
      expect(find.text('+2'), findsOneWidget);
      final rowHeight = tester
          .getSize(find.byType(SvFileTableCell).first)
          .height;
      expect(rowHeight, lessThanOrEqualTo(60));
      await tester.ensureVisible(find.text('+2'));
      await tester.tap(find.text('+2'));
      expect(opened, [0]);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_table_files.png'),
      );
    });
  });

  group('viewer pages', () {
    late _Rig rig;
    setUp(() => rig = _Rig());
    tearDown(() => rig.dispose());

    Future<SvFilePreviewController> open(
      WidgetTester tester,
      List<SvFile> files, {
      int index = 0,
      List<int> ready = const [],
    }) async {
      await _size(tester);
      final c = rig.preview(files, index);
      for (final i in ready) {
        await tester.runAsync(() => c.ensure(c.loads[i]));
      }
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: SvFilePreviewBody(controller: c),
        ),
      );
      await _pumpFor(tester);
      return c;
    }

    testWidgets('opens at the tapped file with a counter; swipe moves', (
      tester,
    ) async {
      final files = [_png, _text, _pdf, _long, _zip];
      final c = await open(tester, files, index: 2);
      expect(c.index.value, 2);
      expect(find.textContaining('3 of 5'), findsOneWidget);
      expect(find.text('Medical certificate.pdf'), findsWidgets);
      await tester.drag(
        find.byKey(const ValueKey('sv-file-pages')),
        const Offset(-400, 0),
      );
      await _pumpFor(tester, 500);
      expect(c.index.value, 3);
      expect(find.textContaining('4 of 5'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('sv-file-pages')),
        const Offset(400, 0),
      );
      await _pumpFor(tester, 500);
      expect(c.index.value, 2);
      expect(find.byTooltip('File actions'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
    });

    testWidgets('one file has no counter', (tester) async {
      await open(tester, [_zip]);
      expect(find.textContaining(' of '), findsNothing);
    });

    testWidgets('golden: sv_file_dialog_image', (tester) async {
      final c = await open(tester, [_png, _text], ready: [0]);
      expect(c.loads[0].isImage, isTrue);
      expect(find.byKey(const ValueKey('sv-file-image')), findsOneWidget);
      await tester.runAsync(() async {
        final context = tester.element(
          find.byKey(const ValueKey('sv-file-image')),
        );
        await precacheImage(
          FileImage(c.loads[0].local!),
          context,
        ).timeout(const Duration(seconds: 3), onTimeout: () {});
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await _pumpFor(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_image.png'),
      );
    });

    testWidgets('golden: sv_file_dialog_text caps at 200 KB', (tester) async {
      final log = SvFile(
        id: _bigText.id,
        name: 'export.log',
        mime: 'text/plain',
        size: _bigText.size,
      );
      final c = await open(tester, [log], ready: [0]);
      expect(c.loads[0].isCut.value, isTrue);
      expect(c.loads[0].text.value!.length, lessThanOrEqualTo(200 * 1024));
      expect(
        find.text('Showing first 200 KB — Download for the full file'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_text.png'),
      );
    });

    testWidgets('golden: sv_file_dialog_other is a clean file card', (
      tester,
    ) async {
      await open(tester, [_long]);
      expect(find.text('XLSX · 1.5 MB'), findsWidgets);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Open with…'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_other.png'),
      );
    });

    testWidgets('progress shows percent and Cancel, which cancels', (
      tester,
    ) async {
      final c = await open(tester, [_zip]);
      final l = c.loads[0];
      l.cancel = CancelToken();
      l.phase.value = SvFilePhase.loading;
      l.progress.value = 0.4;
      await _pumpFor(tester, 100);
      expect(find.text('40%'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      expect(l.cancel!.isCancelled, isTrue);
    });

    testWidgets('golden: sv_file_dialog_error with Retry', (tester) async {
      final c = await open(tester, [_fail]);
      final l = c.loads[0];
      l.problem.value = SvFileProblem.network;
      l.message.value = 'No connection. Check your internet and try again.';
      l.phase.value = SvFilePhase.error;
      await _pumpFor(tester, 100);
      expect(
        find.text('No connection. Check your internet and try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_error.png'),
      );
    });

    testWidgets('not allowed and not found have no Retry', (tester) async {
      final c = await open(tester, [_fail]);
      final l = c.loads[0];
      l.problem.value = SvFileProblem.forbidden;
      l.message.value = "You don't have access to this file.";
      l.phase.value = SvFilePhase.error;
      await _pumpFor(tester, 100);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('the dialog opens with a fade and closes with back', (
      tester,
    ) async {
      await _size(tester);
      final c = rig.preview([_zip]);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => SvFilePreviewDialog.show(context, c),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(find.byType(FadeTransition), findsWidgets);
      await _pumpFor(tester, 300);
      expect(find.byType(SvFilePreviewBody), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await _pumpFor(tester, 400);
      expect(find.byType(SvFilePreviewBody), findsNothing);
    });
  });

  group('fetch, cache, save', () {
    late _Rig rig;
    setUp(() => rig = _Rig());
    tearDown(() => rig.dispose());

    test('progress goes up to 1, then the file is there', () async {
      final c = rig.preview([_png]);
      final seen = <double>[];
      c.loads[0].progress.listen(seen.add);
      final file = await c.ensure(c.loads[0]);
      expect(file, isNotNull);
      expect(c.loads[0].phase.value, SvFilePhase.ready);
      expect(seen.last, 1);
      expect(seen, orderedEquals([...seen]..sort()));
      expect(c.loads[0].isImage, isTrue);
      expect(file!.path.endsWith('.png'), isTrue);
    });

    test('cancel stops the fetch and leaves no partial file', () async {
      final slow = _Rig(
        fetcher: (f, path, p, cancel) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          if (cancel.isCancelled) {
            throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.cancel,
            );
          }
        },
      );
      addTearDown(slow.dispose);
      final c = slow.preview([_zip]);
      final run = c.ensure(c.loads[0]);
      c.cancel();
      expect(await run, isNull);
      expect(c.loads[0].phase.value, SvFilePhase.idle);
      expect(c.loads[0].message.value, isNull);
      expect(slow.temp.listSync(), isEmpty);
    });

    test('an error shows its words and Retry fetches again', () async {
      var tries = 0;
      final flaky = _Rig(
        fetcher: (f, path, p, cancel) async {
          if (tries++ == 0) {
            throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.connectionError,
            );
          }
          await File(path).writeAsBytes([1, 2, 3]);
        },
      );
      addTearDown(flaky.dispose);
      final c = flaky.preview([_zip]);
      await c.ensure(c.loads[0]);
      expect(c.loads[0].phase.value, SvFilePhase.error);
      expect(c.loads[0].problem.value, SvFileProblem.network);
      expect(c.loads[0].message.value, startsWith('No connection'));
      await c.retry();
      expect(c.loads[0].phase.value, SvFilePhase.ready);
      expect(tries, 2);
    });

    test('401 ends the session, 403 and 404 are calm messages', () async {
      Future<SvFilePreviewController> fails(int status, _Rig r) async {
        final c = r.preview([_zip]);
        await c.ensure(c.loads[0]);
        return c;
      }

      SvFileFetcher refuse(int status) => (f, path, p, cancel) async {
        throw DioException(
          requestOptions: RequestOptions(),
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: status,
          ),
          type: DioExceptionType.badResponse,
        );
      };
      final r401 = _Rig(fetcher: refuse(401));
      final r403 = _Rig(fetcher: refuse(403));
      final r404 = _Rig(fetcher: refuse(404));
      addTearDown(() {
        r401.dispose();
        r403.dispose();
        r404.dispose();
      });
      final c401 = await fails(401, r401);
      expect(c401.loads[0].problem.value, SvFileProblem.unauthorized);
      expect(r401.unauthorized, 1);
      expect(
        (await fails(403, r403)).loads[0].problem.value,
        SvFileProblem.forbidden,
      );
      expect(
        (await fails(404, r404)).loads[0].problem.value,
        SvFileProblem.notFound,
      );
      expect(r403.unauthorized, 0);
    });

    test(
      'a file over the preview cap is not fetched to be looked at',
      () async {
        const big = SvFile(
          id: 'c00000000000000000000001',
          name: 'huge.png',
          mime: 'image/png',
          size: 30 * 1024 * 1024,
        );
        final c = rig.preview([big]);
        c.onReady();
        expect(c.loads[0].phase.value, SvFilePhase.error);
        expect(c.loads[0].problem.value, SvFileProblem.tooLarge);
        expect(rig.temp.listSync(), isEmpty);
      },
    );

    test('download opens the save dialog with the clean name', () async {
      rig.onSave = (n) =>
          Uri.parse('content://x/document/primary%3ADownload%2F$n');
      final c = rig.preview([_text]);
      expect(await c.download(), SvDownload.saved);
      expect(rig.asked.single.name, 'notes.txt');
      expect(rig.asked.single.mime, 'text/plain');
      expect(rig.asked.single.bytes, greaterThan(0));

      const evil = SvFile(
        id: 'c00000000000000000000002',
        name: '../../etc/evil.txt',
        mime: 'text/plain',
        size: 3,
      );
      await rig.preview([evil]).download();
      expect(rig.asked.last.name, 'evil.txt');
    });

    test('the name shown is the one the person chose', () {
      expect(
        SvFileRepository.chosenName(
          Uri.parse(
            'content://x/document/primary%3ADownload%2Fnotes%20(1).txt',
          ),
          'notes.txt',
        ),
        'notes (1).txt',
      );
      expect(
        SvFileRepository.chosenName(Uri.file('/Users/a/b/c.pdf'), 'x.pdf'),
        'c.pdf',
      );
      expect(
        SvFileRepository.chosenName(Uri.parse('content://x/'), 'x.pdf'),
        'x.pdf',
      );
    });

    test('cancelling the dialog does nothing and says nothing', () async {
      rig.onSave = (n) => null;
      final c = rig.preview([_text]);
      expect(await c.download(), SvDownload.cancelled);
      expect(rig.asked, hasLength(1));
    });

    test('a failed save is reported; Retry asks the dialog again', () async {
      var fail = true;
      rig.onSave = (n) {
        if (fail) throw Exception('no space');
        return Uri.file('/tmp/$n');
      };
      final c = rig.preview([_text]);
      expect(await c.download(), SvDownload.failed);
      fail = false;
      expect(await c.download(isRetry: true), SvDownload.saved);
      expect(rig.asked, hasLength(2));
      // The fetched copy is reused, not fetched again.
      expect(rig.temp.listSync(), hasLength(1));
    });

    test('text is read as UTF-8, first 200 KB only', () async {
      final log = SvFile(
        id: _bigText.id,
        name: 'export.log',
        mime: 'text/plain',
        size: _bigText.size,
      );
      final c = rig.preview([log]);
      await c.ensure(c.loads[0]);
      expect(c.loads[0].isCut.value, isTrue);
      expect(c.loads[0].text.value!.length, lessThanOrEqualTo(200 * 1024));
      final small = rig.preview([_text]);
      await small.ensure(small.loads[0]);
      expect(small.loads[0].isCut.value, isFalse);
      expect(small.loads[0].text.value, startsWith('Leave notes'));
    });

    test(
      'a picture whose bytes are not a picture shows the file card',
      () async {
        final liar = _Rig(
          fetcher: (f, path, p, c) =>
              File(path).writeAsString('<svg onload=x>'),
        );
        addTearDown(liar.dispose);
        final c = liar.preview([_png]);
        await c.ensure(c.loads[0]);
        expect(c.loads[0].phase.value, SvFilePhase.ready);
        expect(c.loads[0].isShowable.value, isFalse);
      },
    );

    test(
      'the cache keeps the most recently opened files within the limit',
      () async {
        SvFile f(String id, int size) => SvFile(
          id: id,
          name: '$id.bin',
          mime: 'application/zip',
          size: size,
        );
        final a = f('d00000000000000000000001', 1000);
        final b = f('d00000000000000000000002', 1000);
        final padded = _Rig(
          limit: 1500,
          fetcher: (file, path, p, c) =>
              File(path).writeAsBytes(List.filled(file.size, 7)),
        );
        addTearDown(padded.dispose);
        await padded.repo.fetch(a, onProgress: (_) {}, cancel: CancelToken());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await padded.repo.fetch(b, onProgress: (_) {}, cancel: CancelToken());
        expect(await padded.repo.cached(a), isNull);
        expect(await padded.repo.cached(b), isNotNull);
      },
    );

    test('a cache hit is not fetched again', () async {
      var fetched = 0;
      final r = _Rig(
        fetcher: (f, path, p, c) {
          fetched++;
          return File(path).writeAsBytes([1]);
        },
      );
      addTearDown(r.dispose);
      await r.repo.fetch(_zip, onProgress: (_) {}, cancel: CancelToken());
      await r.repo.fetch(_zip, onProgress: (_) {}, cancel: CancelToken());
      expect(fetched, 1);
    });

    test('sign out or another organisation clears the cache', () async {
      await rig.repo.fetch(_png, onProgress: (_) {}, cancel: CancelToken());
      expect(rig.temp.listSync(), isNotEmpty);
      rig.store.current.value = null;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rig.temp.existsSync(), isFalse);
    });
  });
}
