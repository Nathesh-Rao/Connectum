import 'package:connectum/core/log/app_log.dart';
import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/repositories/inbox_repository.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/data/smart_view/sv_file.dart';
import 'package:connectum/features/inbox/models/inbox_card_rows.dart';
import 'package:connectum/features/inbox/models/inbox_query.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:connectum/features/inbox/widgets/inbox_file_chip.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_chips.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_preview_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

InboxRow rowOf(Map<String, dynamic> raw) =>
    InboxRow.tryParse(raw, InboxForm.parseAll(structures))!;

const _a = 'aaaaaaaaaaaaaaaaaaaaaaaa';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbb';
const _c = 'cccccccccccccccccccccccc';
final _tag = 'f' * 64;

Map<String, dynamic> fileInfo(String id, Map<String, dynamic> more) => {
  'id': id,
  ...more,
};

List<InboxCardRow> rowsOf(Map<String, dynamic> rec) =>
    inboxCardRows(rowOf(rec));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsing the file entries', () {
    test('every fact present', () {
      final f = SvFile.tryParse({
        'id': _a,
        'name': 'Quote.PDF',
        'mime': 'application/pdf',
        'size': 52224,
        'ext': 'pdf',
        'uploadedAt': 1764000000000,
        'etag': _tag.toUpperCase(),
      })!;
      expect(f.name, 'Quote.PDF');
      expect(f.mime, 'application/pdf');
      expect(f.size, 52224);
      expect(f.ext, 'pdf');
      expect(f.uploadedAt, 1764000000000);
      expect(f.etag, _tag);
    });

    test('"" and null mean unknown and are left out', () {
      final f = SvFile.tryParse({
        'id': _a,
        'name': '',
        'mime': null,
        'size': null,
        'uploadedAt': null,
        'etag': '',
      })!;
      expect(f.name, 'File');
      expect(f.mime, '');
      expect(f.size, 0);
      expect(f.uploadedAt, isNull);
      expect(f.etag, isNull);
      expect(f.sizeText, '');
    });

    test('wrong types never throw: the entry is kept without the bad part', () {
      final f = SvFile.tryParse({
        'id': _a,
        'name': 5,
        'size': 'big',
        'ext': 7,
        'uploadedAt': 'yesterday',
        'etag': 'not-hex',
      })!;
      expect(f.ext, isNull);
      expect(f.uploadedAt, isNull);
      expect(f.etag, isNull);
      expect(f.size, 0);
    });

    test('a bad id is no file; a list that is not a list is none', () {
      expect(SvFile.tryParse({'id': 'zz', 'name': 'x'}), isNull);
      expect(SvFile.tryParse('nope'), isNull);
      expect(SvFile.listOf([_a], 'nope').single.name, 'File');
      expect(SvFile.listOf('nope', null), isEmpty);
    });

    test(
      'absent: the row keeps no file facts and a card gets the count chip',
      () {
        final rows = rowsOf(
          record(
            1,
            values: {
              'title': 't',
              'attach': [_a, _b],
            },
          ),
        );
        final r = rows.firstWhere((x) => x.name == 'Attachment');
        expect(r.value, '2 files');
        expect(r.hasFileInfo, isFalse);
      },
    );

    test('present: the facts of each id in the order of the ids', () {
      final rows = rowsOf(
        record(
          1,
          values: {
            'title': 't',
            'attach': [_b, _a],
          },
          files: {
            'attach': [
              fileInfo(_a, {'name': 'a.pdf', 'size': 1024, 'ext': 'pdf'}),
              fileInfo(_b, {'name': 'b.png', 'size': 0, 'ext': 'PNG'}),
            ],
          },
        ),
      );
      final r = rows.firstWhere((x) => x.name == 'Attachment');
      expect(r.hasFileInfo, isTrue);
      expect([for (final f in r.files) f.name], ['b.png', 'a.pdf']);
    });

    test('an id with no stored facts shows as "File", never the raw id', () {
      final rows = rowsOf(
        record(
          1,
          values: {
            'title': 't',
            'attach': [_a, _c],
          },
          files: {
            'attach': [
              fileInfo(_a, {'name': 'a.pdf', 'size': 2048}),
            ],
          },
        ),
      );
      final files = rows.firstWhere((x) => x.name == 'Attachment').files;
      expect([for (final f in files) f.name], ['a.pdf', 'File']);
      expect(files.last.id, _c);
    });
  });

  group('chip text', () {
    test('"name  TYPE · size": type in capitals, size left out at 0', () {
      final pdf = SvFile.tryParse({
        'id': _a,
        'name': 'Quote.pdf',
        'size': 52224,
        'ext': 'pdf',
      })!;
      expect(pdf.metaText, 'PDF · 51 KB');
      final none = SvFile.tryParse({
        'id': _a,
        'name': 'notes.txt',
        'size': 0,
        'ext': 'txt',
      })!;
      expect(none.metaText, 'TXT');
    });

    test('the same fallbacks as Smart View for the type', () {
      SvFile f(Map<String, dynamic> m) => SvFile.tryParse({'id': _a, ...m})!;
      expect(f({'name': 'x.csv'}).typeLabel, 'CSV');
      expect(f({'name': 'photo', 'mime': 'image/png'}).typeLabel, 'IMAGE');
      expect(f({'name': 'note', 'mime': 'text/plain'}).typeLabel, 'TEXT');
      expect(f({'name': 'report', 'mime': 'application/pdf'}).typeLabel, 'DOC');
      expect(
        f({'name': 'blob', 'mime': 'application/x-foo'}).typeLabel,
        'FILE',
      );
      expect(f({'name': 'a', 'ext': 'verylongextension'}).typeLabel, 'FILE');
    });

    test('html, svg and xml are never drawn as a page or image', () {
      for (final n in ['a.html', 'a.svg', 'a.xml']) {
        final f = SvFile.tryParse({'id': _a, 'name': n})!;
        expect(f.viewer, anyOf(SvViewer.none, SvViewer.text), reason: n);
        expect(f.viewer, isNot(SvViewer.image), reason: n);
      }
      expect(
        SvFile.tryParse({'id': _a, 'name': 'a', 'mime': 'image/svg+xml'})!.kind,
        SvFileKind.other,
      );
    });

    Future<void> pumpFiles(
      WidgetTester tester,
      InboxRig rig, {
      required double width,
      required double scale,
      required String long,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: InboxCard(
                controller: rig.controller,
                row: rowOf(
                  record(
                    1,
                    values: {
                      'title': 't',
                      'attach': [_a, _b],
                    },
                    files: {
                      'attach': [
                        fileInfo(_a, {
                          'name': 'Q.pdf',
                          'size': 52224,
                          'ext': 'pdf',
                        }),
                        fileInfo(_b, {
                          'name': long,
                          'size': 5000000,
                          'ext': 'pdf',
                        }),
                      ],
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
    }

    InboxRig newRig() {
      final rig = InboxRig(
        files: SvFileRepository(
          dio: Dio(),
          token: () => null,
          origin: '',
          cache: AttachmentCache(Dio()),
          onUnauthorized: () {},
        ),
      )..controller.onInit();
      addTearDown(rig.dispose);
      return rig;
    }

    final long = '${'very-long-file-name-' * 8}.pdf';

    testWidgets('a card shows the name and TYPE · size, cut before the type', (
      tester,
    ) async {
      await pumpFiles(tester, newRig(), width: 390, scale: 1, long: long);
      expect(find.byType(SvFileTile), findsNWidgets(2));
      expect(find.text('Q.pdf'), findsOneWidget);
      expect(find.text('PDF · 51 KB'), findsOneWidget);
      expect(find.text('PDF · 4.8 MB'), findsOneWidget);
      expect(find.text(long), findsNothing, reason: 'the name is cut');
      expect(find.text(_a), findsNothing);
      expect(find.byType(InboxFileChip), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Q.pdf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SvFilePreviewHost), findsOneWidget);
    });

    testWidgets('320 px at text scale 1.5: no overflow, type and size stay', (
      tester,
    ) async {
      await pumpFiles(tester, newRig(), width: 320, scale: 1.5, long: long);
      expect(find.byType(SvFileTile), findsNWidgets(2));
      expect(find.text('PDF · 51 KB'), findsOneWidget);
      expect(find.text('PDF · 4.8 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card built without file facts keeps "n files"', (
      tester,
    ) async {
      final rig = InboxRig(
        files: SvFileRepository(
          dio: Dio(),
          token: () => null,
          origin: '',
          cache: AttachmentCache(Dio()),
          onUnauthorized: () {},
        ),
      )..controller.onInit();
      addTearDown(rig.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InboxCard(
                controller: rig.controller,
                row: rowOf(
                  record(
                    1,
                    values: {
                      'title': 't',
                      'attach': [_a],
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(InboxFileChip), findsOneWidget);
      expect(find.text('1 file'), findsOneWidget);
      expect(find.text(_a), findsNothing);
    });
  });

  group('labels', () {
    test('an option or dropdown value shows its readable caption', () {
      final rows = rowsOf(
        record(
          1,
          values: {'title': 't', 'pick': '2'},
          labels: {'pick': 'Branch Office'},
        ),
      );
      final r = rows.firstWhere((x) => x.name == 'Pick');
      expect(r.value, 'Branch Office');
    });

    test('without a label the value shows as it is', () {
      final rows = rowsOf(record(1, values: {'title': 't', 'pick': '2'}));
      expect(rows.firstWhere((x) => x.name == 'Pick').value, '2');
    });

    test('labels of the wrong type are ignored', () {
      final row = rowOf({
        ...record(1, values: {'title': 't', 'pick': '2'}),
        'labels': 'nope',
      });
      expect(row.labels, isEmpty);
      expect(inboxCardRows(row).firstWhere((x) => x.name == 'Pick').value, '2');
    });
  });

  group('search', () {
    final row = rowOf(
      record(
        7,
        values: {
          'title': 'Laptop',
          'pick': '2',
          'attach': [_a],
        },
        labels: {'pick': 'Branch Office'},
        files: {
          'attach': [
            fileInfo(_a, {'name': 'Invoice-Nov.pdf', 'size': 10}),
          ],
        },
      ),
    );

    test('matches file names, field captions and answer values', () {
      expect(row.hasAnswerText('invoice-nov'), isTrue);
      expect(row.hasAnswerText('attachment'), isTrue);
      expect(row.hasAnswerText('branch off'), isTrue);
      expect(row.hasAnswerText('laptop'), isTrue);
      expect(row.hasAnswerText('nothing like it'), isFalse);
    });

    test('the status field is not an answer', () {
      final r = rowOf(record(1, values: {'title': 't', 'stage': 'Escalated'}));
      expect(r.hasAnswerText('escalated'), isFalse);
    });

    test(
      'the Inbox search uses it, together with form, people and status',
      () async {
        final rig = InboxRig();
        addTearDown(rig.dispose);
        rig.routes['records.query'] = (_) => queryReply([
          record(
            7,
            values: {
              'title': 'Laptop',
              'attach': [_a],
            },
            files: {
              'attach': [
                fileInfo(_a, {'name': 'Invoice-Nov.pdf'}),
              ],
            },
          ),
          record(8, values: {'title': 'Chair'}),
        ]);
        rig.controller.onInit();
        await settle();
        rig.controller.onQueryChanged('invoice-nov');
        expect(rig.ids, [7]);
        rig.controller.onQueryChanged('attachment');
        expect(rig.ids, [7]);
        rig.controller.onQueryChanged('chair');
        expect(rig.ids, [8]);
        rig.controller.onQueryChanged('thing');
        expect(rig.ids, [8, 7]);
      },
    );
  });

  group('the request', () {
    test(
      'the list read adds withDetails and fileMeta:2, never other args',
      () async {
        final rig = InboxRig();
        addTearDown(rig.dispose);
        rig.routes['records.query'] = (_) => queryReply([record(1)]);
        await rig.inbox.query(const InboxQuery());
        final a = rig.argsOf('records.query').single;
        expect(a['withDetails'], true);
        expect(a['fileMeta'], 2);
        expect(a['fileMeta'], isA<int>());
      },
    );

    test('the facets read does not carry them', () async {
      final rig = InboxRig();
      addTearDown(rig.dispose);
      rig.routes['records.query'] = (_) => {
        'formCounts': <String, dynamic>{},
        'people': <String, dynamic>{},
        'submissions': <dynamic>[],
        'total': 0,
      };
      await rig.inbox.queryFacets(const InboxQuery(isFacets: true));
      final a = rig.argsOf('records.query').single;
      expect(a['facets'], true);
      expect(a.containsKey('withDetails'), isFalse);
      expect(a.containsKey('fileMeta'), isFalse);
    });

    test('paged reads carry them too', () async {
      final rig = InboxRig();
      addTearDown(rig.dispose);
      rig.routes['records.query'] = (_) =>
          queryReply([record(1)], hasMore: true, total: 5);
      await rig.inbox.query(const InboxQuery());
      await rig.inbox.query(const InboxQuery(), offset: 1);
      for (final a in rig.argsOf('records.query')) {
        expect(InboxRepository.fileArgs.keys, everyElement(isIn(a.keys)));
      }
    });

    test(
      'an older server that ignores them still gives rows without files',
      () async {
        final rig = InboxRig();
        addTearDown(rig.dispose);
        rig.routes['records.query'] = (_) => queryReply([
          record(
            1,
            values: {
              'title': 't',
              'attach': [_a],
            },
          ),
        ]);
        final page = await rig.inbox.query(const InboxQuery());
        expect(page!.rows.single.files, isEmpty);
      },
    );

    test('each page read is timed in the log', () async {
      final rig = InboxRig();
      addTearDown(rig.dispose);
      rig.routes['records.query'] = (_) => queryReply([record(1)]);
      final out = <String>[];
      final old = AppLog.sink;
      AppLog.sink = out.add;
      addTearDown(() => AppLog.sink = old);
      await rig.inbox.query(const InboxQuery());
      expect(
        out.any((l) => l.contains('records.query page') && l.contains('ms=')),
        isTrue,
      );
      expect(
        out.join().contains('Record 1'),
        isFalse,
        reason: 'no record text',
      );
    });
  });
}
