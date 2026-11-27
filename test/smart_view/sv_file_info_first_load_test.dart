import 'package:connectum/core/log/app_log.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sv_support.dart';

const _id = 'a00000000000000000000001';
final _tag = 'a1' * 32;

Map<String, dynamic> _entry({bool isMeta = true}) => {
  'id': _id,
  'name': 'Quarterly report.pdf',
  'mime': 'application/pdf',
  'size': 52224,
  if (isMeta) ...{'ext': 'pdf', 'uploadedAt': 1763900000000, 'etag': _tag},
};

Map<String, dynamic> _fileRow(int id, {bool isDetailed = true}) =>
    ownRow(
        id,
        tstruct: 'everyfield',
        values: {
          'doc': [_id],
        },
      )
      ..['files'] = isDetailed
          ? {
              'doc': [_entry()],
            }
          : <String, dynamic>{};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parse', () {
    test('a first page with fileMeta gives size, ext, uploadedAt, etag', () {
      final row = SvRow.tryParse(_fileRow(1), isReceived: false)!;
      final f = row.filesOf('doc').single;
      expect(f.metaText, 'PDF · 51 KB');
      expect(f.ext, 'pdf');
      expect(f.uploadedAt, isNotNull);
      expect(f.etag, _tag);
    });

    test('without the fileMeta fields type and size still show', () {
      final raw = _fileRow(1)
        ..['files'] = {
          'doc': [_entry(isMeta: false)],
        };
      final f = SvRow.tryParse(raw, isReceived: false)!.filesOf('doc').single;
      expect(f.metaText, 'PDF · 51 KB');
      expect(f.ext, isNull);
      expect(f.etag, isNull);
    });

    test('a file id with no entry has no info at all', () {
      final row = SvRow.tryParse(
        _fileRow(1, isDetailed: false),
        isReceived: false,
      )!;
      expect(row.filesOf('doc').single.metaText, 'FILE');
    });

    testWidgets('the chip draws type and size from the entry', (tester) async {
      final row = SvRow.tryParse(_fileRow(1), isReceived: false)!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SvFileChip(file: row.filesOf('doc').single)),
        ),
      );
      expect(find.text('PDF · 51 KB'), findsOneWidget);
      final bare = SvRow.tryParse(
        _fileRow(1, isDetailed: false),
        isReceived: false,
      )!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SvFileChip(file: bare.filesOf('doc').single)),
        ),
      );
      expect(find.text('FILE'), findsOneWidget);
    });
  });

  group('a record first seen through an event', () {
    late SvRig rig;
    late SvTable table;
    final lines = <String>[];

    Future<void> pump() async {
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      rig = SvRig();
      lines.clear();
      AppLog.sink = lines.add;
      rig.socket.answers[SvCmd.sources] = captured('004');
      final all = await rig.repo.sources();
      table = rig.repo.open(all.firstWhere((s) => s.name == 'everyfield'));
      final pager = listPager([_fileRow(10)]);
      rig.socket.answers['submissions.list'] = pager;
      rig.socket.answers['records.mine'] = minePager(const {});
      await rig.repo.load(table);
      rig.socket.calls.clear();
    });

    tearDown(() => AppLog.sink = null);

    Map<String, dynamic> created(int id) => {
      'type': 'sd_event',
      'event': 'submissions_changed',
      'data': {'id': id, 'tstruct': 'everyfield', 'action': 'created'},
    };

    test('first load: details arrive and the parse is logged', () {
      final f = table.rowOf(10)!.filesOf('doc').single;
      expect(f.metaText, 'PDF · 51 KB');
      expect(
        lines.any(
          (l) =>
              l.contains('sv_files_parse') &&
              l.contains('path=submissions.list') &&
              l.contains('etag=1'),
        ),
        isTrue,
      );
    });

    test(
      'submission.get without files: the newest page repairs the row',
      () async {
        rig.socket.answers['submission.get'] = {
          'submission': _fileRow(20, isDetailed: false),
        };
        rig.socket.answers['submissions.list'] = listPager([
          _fileRow(20),
          _fileRow(10),
        ]);
        rig.repo.onEvent(created(20));
        await pump();
        expect(rig.count('submission.get'), 1);
        expect(rig.count('submissions.list'), 1);
        expect(table.rowOf(20)!.filesOf('doc').single.metaText, 'PDF · 51 KB');
        expect(
          lines.any(
            (l) =>
                l.contains('path=submission.get') &&
                l.contains('rowsWithoutDetails=1'),
          ),
          isTrue,
        );
      },
    );

    test(
      'submission.get that carries files keeps them, no extra read',
      () async {
        rig.socket.answers['submission.get'] = {'submission': _fileRow(21)};
        rig.repo.onEvent(created(21));
        await pump();
        expect(rig.count('submissions.list'), 0);
        expect(table.rowOf(21)!.filesOf('doc').single.metaText, 'PDF · 51 KB');
      },
    );
  });
}
