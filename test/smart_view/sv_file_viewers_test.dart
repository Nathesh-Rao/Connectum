import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:connectum/core/debug/seed_smart_files.dart';
import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/preview/sv_preview_parsers.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/data/smart_view/sv_file.dart';
import 'package:connectum/features/smart_view/sv_file_preview_controller.dart';
import 'package:connectum/features/smart_view/viewers/sv_media_player.dart';
import 'package:connectum/features/smart_view/viewers/sv_media_viewer.dart';
import 'package:connectum/features/smart_view/viewers/sv_pdf_viewer.dart';
import 'package:connectum/features/smart_view/viewers/sv_sheet_viewer.dart';
import 'package:connectum/features/smart_view/viewers/sv_viewers.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_chips.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_preview_dialog.dart';
import 'package:connectum/features/smart_view/widgets/sv_record_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

// Fakes only: a fake downloader, temp folders, fake players, no server, no
// phone. Platform views and plugins (pdfrx, video_player) cannot render in
// tests, so the goldens of those bodies use the fake viewers.

SvFile _byId(String id) => SeedSmartFiles.files.firstWhere((f) => f.id == id);

final _png = _byId(SeedSmartFiles.imageId);
final _text = _byId(SeedSmartFiles.textId);
final _csv = _byId(SeedSmartFiles.bigTextId);
final _pdf = _byId(SeedSmartFiles.pdfId);
final _long = _byId(SeedSmartFiles.longId);
final _zip = _byId(SeedSmartFiles.zipId);
final _docx = _byId(SeedSmartFiles.docxId);
final _pptx = _byId(SeedSmartFiles.pptxId);
final _wav = _byId(SeedSmartFiles.audioId);
const _clip = SvFile(
  id: 'b00000000000000000000001',
  name: 'clip.mp4',
  mime: 'video/mp4',
  size: 1000,
);

Future<void> _fast(
  SvFile f,
  String path,
  void Function(double) onProgress,
  CancelToken cancel,
) => SeedSmartFiles.fetch(f, path, onProgress, cancel, step: Duration.zero);

class _Rig {
  _Rig({SvFileFetcher? fetcher}) {
    temp = Directory.systemTemp.createTempSync('svv_temp');
    repo = SvFileRepository(
      dio: Dio(),
      token: () => null,
      origin: '',
      cache: AttachmentCache(Dio()),
      onUnauthorized: () {},
      store: FakeStore(),
      fetcher: fetcher ?? _fast,
      tempDir: () async => temp..createSync(recursive: true),
      saver: (name, file, mime) async => null,
    );
  }

  late final Directory temp;
  late final SvFileRepository repo;

  SvFilePreviewController preview(List<SvFile> files, [int index = 0]) =>
      SvFilePreviewController(files: files, repo: repo, index: index);

  void dispose() {
    repo.dispose();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

/// A player that records what the controls ask of it.
class _FakePlayer extends SvMediaPlayer {
  _FakePlayer() : super.test();

  final calls = <String>[];
  bool isDisposed = false;

  @override
  Future<void> init() async {
    state.value = const SvMediaState(
      isReady: true,
      duration: Duration(seconds: 90),
      position: Duration(seconds: 5),
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    state.value = SvMediaState(
      isReady: true,
      isPlaying: true,
      duration: state.value.duration,
      position: state.value.position,
    );
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> skip(Duration by) async => calls.add('skip ${by.inSeconds}');

  @override
  Future<void> toggleMute() async => calls.add('mute');

  @override
  Future<void> setSpeed(double speed) async => calls.add('speed $speed');

  @override
  Future<void> seekTo(Duration to) async => calls.add('seek ${to.inSeconds}');

  @override
  Widget surface() => const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

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

SvSource _source() => const SvSource(
  name: 's',
  caption: 'S',
  keyField: 'title',
  fields: [
    SvField(name: 'title', caption: 'Title'),
    SvField(name: 'doc', caption: 'Documents', type: 'file'),
  ],
);

SvRow _row(int id, List<SvFile> files) => SvRow(
  id: id,
  tstruct: 's',
  by: 'me',
  ts: DateTime(2026, 11, 18, 12).millisecondsSinceEpoch,
  values: {
    'title': 'Row $id',
    'doc': [for (final f in files) f.id],
  },
  files: {
    'doc': [
      for (final f in files)
        {'id': f.id, 'name': f.name, 'mime': f.mime, 'size': f.size},
    ],
  },
);

/// Chips with the fold kept per record id, like the screen's controller.
class _Folds extends StatefulWidget {
  const _Folds({required this.records});

  final Map<int, List<SvFile>> records;

  @override
  State<_Folds> createState() => _FoldsState();
}

class _FoldsState extends State<_Folds> {
  final open = <int>{};

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final e in widget.records.entries)
        SvFileChips(
          key: ValueKey('rec-${e.key}'),
          files: e.value,
          onOpen: (_, _) {},
          isExpanded: open.contains(e.key),
          onToggle: () => setState(() {
            if (!open.remove(e.key)) open.add(e.key);
          }),
        ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final five = [_png, _text, _pdf, _long, _zip];

  group('tiles', () {
    testWidgets('every tile has the same width and height', (tester) async {
      await _size(tester);
      await tester.pumpWidget(
        _host(SvFileChips(files: [_png, _long, _text], onOpen: (_, _) {})),
      );
      final sizes = [
        for (final e in tester.elementList(find.byType(SvFileTile))) e.size!,
      ];
      expect(sizes, hasLength(3));
      expect(sizes.map((s) => s.width).toSet(), hasLength(1));
      expect(sizes.map((s) => s.height).toSet(), hasLength(1));
      expect(sizes.first.width, 360 - 32);
    });

    testWidgets('"+N more" expands in place, "Show less" folds, per record', (
      tester,
    ) async {
      await _size(tester, const Size(360, 900));
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(child: _Folds(records: {1: five, 2: five})),
        ),
      );
      expect(find.byType(SvFileTile), findsNWidgets(6));
      await tester.tap(find.text('+2 more').first);
      await _pumpFor(tester, 300);
      expect(find.byType(SvFileTile), findsNWidgets(8));
      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('+2 more'), findsOneWidget);
      await tester.tap(find.text('Show less'));
      await _pumpFor(tester, 300);
      expect(find.byType(SvFileTile), findsNWidgets(6));
      expect(find.text('Show less'), findsNothing);
    });

    testWidgets('golden: sv_file_tiles_expanded', (tester) async {
      await _size(tester, const Size(360, 420));
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: SvFileChips(
              files: five,
              onOpen: (_, _) {},
              isExpanded: true,
              onToggle: () {},
            ),
          ),
        ),
      );
      await _pumpFor(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_tiles_expanded.png'),
      );
    });

    testWidgets('record sheet shows all files with no "+N"; golden', (
      tester,
    ) async {
      await _size(tester, const Size(360, 760));
      final data = SmartViewColumns.of(_source()).cardOf(_row(1, five));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SvRecordSheetBody(data: data, onOpenFiles: (_, _) {}),
          ),
        ),
      );
      await _pumpFor(tester);
      expect(find.byType(SvFileTile), findsNWidgets(5));
      expect(find.textContaining('more'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_record_sheet_files.png'),
      );
    });
  });

  group('parsers', () {
    test('csv: quotes, semicolons, tabs, embedded newlines', () {
      final q = SvPreviewParsers.parseCsv(
        'a,b\n"x, y","he said ""hi"""\n"line1\nline2",z\n',
      );
      expect(q.rows, [
        ['a', 'b'],
        ['x, y', 'he said "hi"'],
        ['line1\nline2', 'z'],
      ]);
      final semi = SvPreviewParsers.parseCsv('a;b;c\r\n1;2;3\r\n');
      expect(semi.rows, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
      final tab = SvPreviewParsers.parseCsv('a\tb\n1\t2');
      expect(tab.rows.last, ['1', '2']);
      expect(SvPreviewParsers.parseCsv('').rows, isEmpty);
      expect(SvPreviewParsers.parseCsv('﻿a,b').rows.first.first, 'a');
    });

    test('csv caps rows and columns', () {
      final rows = [for (var i = 0; i < 600; i++) '$i,x'].join('\n');
      final t = SvPreviewParsers.parseCsv(rows);
      expect(t.rows, hasLength(500));
      expect(t.isCut, isTrue);
      final wide = SvPreviewParsers.parseCsv(
        List.generate(60, (i) => 'c$i').join(','),
      );
      expect(wide.rows.first, hasLength(50));
      expect(wide.isCut, isTrue);
    });

    test('docx text with headings, bold and list items', () {
      final doc = SvPreviewParsers.parseDocx(
        Uint8List.fromList((SeedSmartFiles.bytesOf(_docx))),
      )!;
      final blocks = doc.pages.single;
      expect(blocks.first.text, 'Leave policy');
      expect(blocks.first.style, SvBlockStyle.heading);
      expect(blocks[2].isBold, isTrue);
      expect(blocks[3].style, SvBlockStyle.list);
      expect(doc.isSlides, isFalse);
      expect(SvPreviewParsers.parseDocx(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('pptx gives a page per slide in order', () {
      final zip = Archive()
        ..addFile(
          ArchiveFile.string(
            'ppt/slides/slide10.xml',
            '<a:p><a:r><a:t>Ten &amp; last</a:t></a:r></a:p>',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'ppt/slides/slide2.xml',
            '<a:p><a:r><a:t>Two</a:t></a:r></a:p>',
          ),
        );
      final doc = SvPreviewParsers.parsePptx(
        Uint8List.fromList(ZipEncoder().encode(zip)),
      )!;
      expect(doc.isSlides, isTrue);
      expect(doc.pages.map((p) => p.first.text), ['Two', 'Ten & last']);
    });

    test('zip lists entries with sizes and totals, without extracting', () {
      final l = SvPreviewParsers.listZip(
        Uint8List.fromList(SeedSmartFiles.bytesOf(_zip)),
      )!;
      expect(l.totalFiles, 3);
      expect(l.entries.map((e) => e.name), contains('itinerary.txt'));
      expect(l.totalSize, 12 + 900 + 4000);
      expect(SvPreviewParsers.listZip(Uint8List.fromList([0, 1])), isNull);
    });

    test('json pretty-prints valid JSON under 200 KB only', () {
      expect(SvPreviewParsers.prettyJson('{"a":1}'), '{\n  "a": 1\n}');
      expect(SvPreviewParsers.prettyJson('{oops'), isNull);
      expect(SvPreviewParsers.prettyJson('hello'), isNull);
      expect(SvPreviewParsers.prettyJson('["${'x' * 210000}"]'), isNull);
    });

    test('viewer by type; SVG and legacy Office have none', () {
      expect(_pdf.viewer, SvViewer.pdf);
      expect(_csv.viewer, SvViewer.sheet);
      expect(_docx.viewer, SvViewer.docx);
      expect(_pptx.viewer, SvViewer.pptx);
      expect(_zip.viewer, SvViewer.zip);
      expect(_wav.viewer, SvViewer.audio);
      expect(_clip.viewer, SvViewer.video);
      expect(_long.viewer, SvViewer.none);
      expect(
        SvFile(id: 'a' * 24, name: 'x.svg', mime: 'image/svg+xml').viewer,
        SvViewer.none,
      );
      expect(SvFile(id: 'a' * 24, name: 'old.doc').viewer, SvViewer.none);
      expect(SvFileRepository.isImageHead([0x89, 0x50, 0x4E, 0x47]), isTrue);
      expect(SvFileRepository.isImageHead('<svg'.codeUnits), isFalse);
    });
  });

  group('viewers', () {
    late _Rig rig;
    setUp(() => rig = _Rig());
    tearDown(() => rig.dispose());

    Future<SvFilePreviewController> open(
      WidgetTester tester,
      List<SvFile> files, {
      int index = 0,
      SvViewers viewers = const SvViewers(),
      bool isFull = false,
    }) async {
      await _size(tester);
      final c = rig.preview(files, index);
      c.isFull.value = isFull;
      await tester.runAsync(() async {
        for (final l in c.loads) {
          if (l.file.viewer != SvViewer.none) await c.ensure(l);
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: SvFilePreviewBody(controller: c, viewers: viewers),
        ),
      );
      await _pumpFor(tester);
      return c;
    }

    testWidgets('pdf chrome: indicator, go to page, previous and next', (
      tester,
    ) async {
      await _size(tester);
      final went = <int>[];
      var page = 3;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => Align(
                alignment: Alignment.bottomCenter,
                child: SvPdfChrome(
                  page: page,
                  count: 12,
                  onGoTo: (n) {
                    went.add(n);
                    set(() => page = n);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('3 / 12'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Next page'));
      await tester.pump();
      expect(went, [4]);
      await tester.tap(find.bySemanticsLabel('Previous page'));
      await tester.pump();
      expect(went, [4, 3]);
      await tester.tap(find.byKey(const ValueKey('sv-pdf-pill')));
      await _pumpFor(tester, 500);
      expect(find.text('Go to page'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '99');
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(find.text('Enter a page from 1 to 12'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '7');
      await tester.tap(find.text('Go'));
      await _pumpFor(tester, 500);
      expect(went.last, 7);
      expect(find.text('7 / 12'), findsOneWidget);
    });

    testWidgets('video controls call the player; pause when inactive', (
      tester,
    ) async {
      await _size(tester);
      final players = <_FakePlayer>[];
      final load = SvFileLoad(_clip)..local = File('unused');
      Widget build(bool isActive) => MaterialApp(
        home: Scaffold(
          body: SvMediaViewer(
            load: load,
            isActive: isActive,
            factory: (_) => _FakePlayer().._add(players),
          ),
        ),
      );
      await tester.pumpWidget(build(true));
      await tester.pump();
      final p = players.single;
      expect(find.text('0:05'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sv-media-play')));
      await tester.tap(find.bySemanticsLabel('Forward 10 seconds'));
      await tester.tap(find.bySemanticsLabel('Back 10 seconds'));
      await tester.tap(find.bySemanticsLabel('Mute'));
      await tester.tap(find.byTooltip('Playback speed'));
      await _pumpFor(tester, 400);
      await tester.tap(find.text('1.5×').last);
      await _pumpFor(tester, 400);
      expect(p.calls, ['play', 'skip 10', 'skip -10', 'mute', 'speed 1.5']);
      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(p.calls.last, 'pause');
      expect(p.isDisposed, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(p.isDisposed, isTrue);
    });

    testWidgets('swiping away releases the player', (tester) async {
      final players = <_FakePlayer>[];
      final c = await open(tester, [
        _wav,
        _text,
      ], viewers: SvViewers(mediaPlayer: (_) => _FakePlayer().._add(players)));
      expect(players, hasLength(1));
      await tester.drag(
        find.byKey(const ValueKey('sv-file-pages')),
        const Offset(-400, 0),
      );
      await _pumpFor(tester, 600);
      expect(c.index.value, 1);
      expect(players.first.isDisposed, isTrue);
    });

    testWidgets('closing cancels a download in flight', (tester) async {
      final r = _Rig(
        fetcher: (f, path, onProgress, cancel) async {
          await Future<void>.delayed(const Duration(seconds: 30));
        },
      );
      addTearDown(r.dispose);
      final c = r.preview([_zip]);
      final l = c.loads.first;
      c.ensure(l);
      await tester.pump(const Duration(milliseconds: 10));
      expect(l.phase.value, SvFilePhase.loading);
      c.onClose();
      expect(l.cancel!.isCancelled, isTrue);
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('sheet tabs switch; the notice shows when cut', (tester) async {
      await _size(tester);
      final book = SvSheetBook([
        const SvSheetTable(
          name: 'Leave',
          rows: [
            ['Name', 'Days'],
            ['Ana', '3'],
          ],
        ),
        const SvSheetTable(
          name: 'Sick',
          isCut: true,
          rows: [
            ['Who', 'When'],
            ['Raj', 'Mon'],
          ],
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SvSheetViewer(book: book)),
        ),
      );
      expect(find.text('Ana'), findsOneWidget);
      expect(find.byKey(const ValueKey('sv-sheet-notice')), findsNothing);
      await tester.tap(find.text('Sick'));
      await tester.pump();
      expect(find.text('Raj'), findsOneWidget);
      expect(
        find.text('Showing first 500 rows — Download for the full file'),
        findsOneWidget,
      );
    });

    testWidgets('golden: sv_file_dialog_sheet (csv, row cap)', (tester) async {
      final c = await open(tester, [_csv]);
      expect(c.loads.first.sheet!.tables.single.rows, hasLength(500));
      expect(c.loads.first.sheet!.tables.single.isCut, isTrue);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_sheet.png'),
      );
    });

    testWidgets('golden: sv_file_dialog_docx', (tester) async {
      final c = await open(tester, [_docx]);
      expect(c.loads.first.doc, isNotNull);
      expect(
        find.text('Text preview — open the file for full formatting'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_docx.png'),
      );
    });

    testWidgets('pptx shows Slide 1 / 3 and moves', (tester) async {
      await open(tester, [_pptx]);
      expect(find.text('Slide 1 / 3'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Next slide'));
      await tester.pump();
      expect(find.text('Slide 2 / 3'), findsOneWidget);
      expect(find.text('Handover - step 2'), findsOneWidget);
    });

    testWidgets('golden: sv_file_dialog_zip', (tester) async {
      await open(tester, [_zip]);
      expect(find.text('3 files · 5 KB'), findsOneWidget);
      expect(find.text('visa/form.pdf'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_zip.png'),
      );
    });

    testWidgets('golden: sv_file_dialog_pdf (fake viewer)', (tester) async {
      await open(
        tester,
        [_pdf, _text],
        viewers: SvViewers(
          pdf: (context, load, isActive) => Stack(
            children: [
              const ColoredBox(
                color: Color(0xFFF1F3F9),
                child: Center(child: Text('PDF page (fake viewer)')),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: SvPdfChrome(page: 3, count: 12, onGoTo: (_) {}),
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.text('3 / 12'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_pdf.png'),
      );
    });

    testWidgets('golden: sv_file_dialog_video (fake player)', (tester) async {
      await open(tester, [
        _clip,
      ], viewers: SvViewers(mediaPlayer: (_) => _FakePlayer()));
      expect(find.byKey(const ValueKey('sv-media-play')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_video.png'),
      );
    });

    testWidgets('golden: sv_file_dialog_fullscreen', (tester) async {
      await open(tester, [_zip, _text], isFull: true);
      expect(find.bySemanticsLabel('Exit full screen'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sv_file_dialog_fullscreen.png'),
      );
    });

    testWidgets('full screen: icon states and Back order', (tester) async {
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
      await _pumpFor(tester, 400);
      final card = find.byKey(const ValueKey('sv-file-dialog'));
      expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
      final dialogSize = tester.getSize(card);
      expect(dialogSize.width, 360 - 32);
      expect(dialogSize.height, closeTo(640 * 0.78, 1));
      await tester.tap(find.bySemanticsLabel('Full screen'));
      await _pumpFor(tester, 400);
      expect(c.isFull.value, isTrue);
      expect(find.byIcon(Icons.close_fullscreen_rounded), findsOneWidget);
      expect(tester.getSize(card), const Size(360, 640));
      await tester.binding.handlePopRoute();
      await _pumpFor(tester, 400);
      expect(c.isFull.value, isFalse);
      expect(find.byType(SvFilePreviewBody), findsOneWidget);
      expect(tester.getSize(card).width, 360 - 32);
      await tester.binding.handlePopRoute();
      await _pumpFor(tester, 500);
      expect(find.byType(SvFilePreviewBody), findsNothing);
    });

    testWidgets('barrier tap closes the dialog', (tester) async {
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
      await _pumpFor(tester, 400);
      await tester.tapAt(const Offset(180, 10));
      await _pumpFor(tester, 500);
      expect(find.byType(SvFilePreviewBody), findsNothing);
    });

    testWidgets('dots show up to 8 files; subtitle has kind, size, position', (
      tester,
    ) async {
      await open(tester, five);
      expect(find.byKey(const ValueKey('sv-file-dots')), findsOneWidget);
      expect(find.text('PNG · 833 B · 1 of 5'), findsOneWidget);
    });
  });
}

extension on _FakePlayer {
  void _add(List<_FakePlayer> into) => into.add(this);
}
