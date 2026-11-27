import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/sv_file.dart';
import 'package:connectum/features/smart_view/sv_file_preview_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

// Fakes only: a fake HTTP adapter and temp folders. No server, no phone.

const _id = 'a00000000000000000000001';
final _tag1 = 'a1' * 32;
final _tag2 = 'b2' * 32;

Map<String, dynamic> _entry([Map<String, dynamic> extra = const {}]) => {
  'id': _id,
  'name': 'Quarterly report.pdf',
  'mime': 'application/pdf',
  'size': 52224,
  'ext': 'pdf',
  'uploadedAt': DateTime(2026, 11, 24, 12).millisecondsSinceEpoch,
  'etag': _tag1,
  ...extra,
};

/// What the fake server answers to one request.
class _Reply {
  _Reply(this.status, {this.body = const [], this.etag, this.json, this.error});

  final int status;
  final List<int> body;
  final String? etag;
  final Object? json;
  final DioExceptionType? error;
}

class _Fake implements HttpClientAdapter {
  final seen = <RequestOptions>[];
  final queue = <_Reply>[];
  Completer<void>? hold;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    await hold?.future;
    final r = queue.removeAt(0);
    if (r.error != null) {
      throw DioException(requestOptions: options, type: r.error!);
    }
    final bytes = r.json != null ? utf8.encode(jsonEncode(r.json)) : r.body;
    return ResponseBody.fromBytes(
      bytes,
      r.status,
      headers: {
        if (r.etag != null) 'etag': [r.etag!],
        'content-length': ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Rig {
  _Rig({int limit = SvFileRepository.maxCacheBytes, int files = 24}) {
    temp = Directory.systemTemp.createTempSync('svm_temp');
    final dio = Dio()..httpClientAdapter = http;
    repo = SvFileRepository(
      dio: dio,
      token: () => 'TOKEN',
      origin: 'https://example.test',
      cache: AttachmentCache(Dio()),
      onUnauthorized: () => unauthorized++,
      store: store,
      cacheLimit: limit,
      cacheFiles: files,
      tempDir: () async => temp..createSync(recursive: true),
    );
  }

  final http = _Fake();
  final store = FakeStore();
  late final Directory temp;
  late final SvFileRepository repo;
  int unauthorized = 0;

  Future<SvFetched> open(SvFile f) =>
      repo.fetch(f, onProgress: (_) {}, cancel: CancelToken());

  Future<SvFileException> fails(SvFile f) async {
    try {
      await open(f);
    } on SvFileException catch (e) {
      return e;
    }
    fail('expected a SvFileException');
  }

  List<String> get names => [
    for (final e in temp.existsSync() ? temp.listSync() : <FileSystemEntity>[])
      e.path.split('/').last,
  ]..sort();

  String? header(int i, String name) => http.seen[i].headers[name]?.toString();

  void dispose() {
    repo.dispose();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

SvFile _file([String id = _id, String name = 'a.pdf']) =>
    SvFile(id: id, name: name, mime: 'application/pdf', size: 3);

String _idN(int n) => 'c${n.toString().padLeft(23, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsing the file entry', () {
    test('every new field present', () {
      final f = SvFile.tryParse(_entry())!;
      expect(f.name, 'Quarterly report.pdf');
      expect(f.size, 52224);
      expect(f.ext, 'pdf');
      expect(f.uploadedAt, DateTime(2026, 11, 24, 12).millisecondsSinceEpoch);
      expect(f.etag, _tag1);
    });

    test('an older server: no new fields, the name decides the type', () {
      final f = SvFile.tryParse({
        'id': _id,
        'name': 'a.xlsx',
        'mime': 'x',
        'size': 9,
      })!;
      expect(f.ext, isNull);
      expect(f.uploadedAt, isNull);
      expect(f.etag, isNull);
      expect(f.typeLabel, 'XLSX');
    });

    test('wrong types are dropped, never thrown', () {
      final f = SvFile.tryParse(
        _entry({'ext': 5, 'uploadedAt': 'x', 'etag': 7, 'size': 'big'}),
      )!;
      expect(f.ext, isNull);
      expect(f.uploadedAt, isNull);
      expect(f.etag, isNull);
      expect(f.size, 0);
      expect(SvFile.tryParse(_entry({'size': -4}))!.size, 0);
      expect(SvFile.tryParse(_entry({'uploadedAt': 0}))!.uploadedAt, isNull);
      expect(SvFile.tryParse(_entry({'name': null}))!.name, 'File');
      expect(SvFile.tryParse('x'), isNull);
      expect(SvFile.tryParse(_entry({'id': 'nope'})), isNull);
    });

    test('ext "" means no extension, uploadedAt and etag may be null', () {
      final f = SvFile.tryParse(
        _entry({'name': 'README', 'ext': '', 'uploadedAt': null, 'etag': null}),
      )!;
      expect(f.ext, '');
      expect(f.uploadedAt, isNull);
      expect(f.etag, isNull);
    });

    test('an etag must be bare 64-hex: quoted, short or weak is null', () {
      expect(SvFile.tryParse(_entry({'etag': '"$_tag1"'}))!.etag, isNull);
      expect(SvFile.tryParse(_entry({'etag': 'W/"$_tag1"'}))!.etag, isNull);
      expect(SvFile.tryParse(_entry({'etag': 'abc'}))!.etag, isNull);
      expect(
        SvFile.tryParse(_entry({'etag': _tag1.toUpperCase()}))!.etag,
        _tag1,
      );
    });

    test('a name keeps its first 120 characters', () {
      final f = SvFile.tryParse(_entry({'name': '${'x' * 300}.pdf'}))!;
      expect(f.name.length, 120);
      final emoji = SvFile.tryParse(_entry({'name': '😀' * 100}))!;
      expect(emoji.name.length, 120);
      expect(emoji.name.runes.length, 60);
    });

    test('a file id with no entry is a chip named File with no size', () {
      final list = SvFile.listOf(
        [_id],
        [
          _entry({'id': 'b00000000000000000000009'}),
        ],
      );
      expect(list.single.name, 'File');
      expect(list.single.size, 0);
      expect(list.single.metaText, 'FILE');
      expect(SvFile.listOf([_id], null).single.name, 'File');
    });

    test('a grid section row keys files by <section>.<row>.<field>', () {
      final row = SvRow(
        id: 1,
        tstruct: 's',
        by: 'me',
        ts: 1,
        values: {
          'doc': [_id],
          'items.0.pic': ['b00000000000000000000002'],
        },
        files: {
          'doc': [_entry()],
          'items.0.pic': [
            _entry({
              'id': 'b00000000000000000000002',
              'name': 'p.png',
              'ext': 'png',
              'etag': _tag2,
            }),
          ],
        },
      );
      expect(row.filesOf('doc').single.etag, _tag1);
      final grid = row.filesOf('items.0.pic').single;
      expect(grid.name, 'p.png');
      expect(grid.etag, _tag2);
    });
  });

  group('chip text and header', () {
    SvFile f({
      String name = 'a.pdf',
      String mime = '',
      int size = 0,
      String? ext,
      int? at,
    }) => SvFile(
      id: _id,
      name: name,
      mime: mime,
      size: size,
      ext: ext,
      uploadedAt: at,
    );

    test('name  TYPE · size', () {
      final x = f(name: 'Quarterly report.pdf', size: 52224, ext: 'pdf');
      expect(x.metaText, 'PDF · 51 KB');
    });

    test('type fallbacks when there is no extension', () {
      expect(f(name: 'x', ext: '', mime: 'image/png').typeLabel, 'IMAGE');
      expect(f(name: 'x', ext: '', mime: 'text/plain').typeLabel, 'TEXT');
      expect(f(name: 'x', ext: '', mime: 'application/pdf').typeLabel, 'DOC');
      expect(
        f(name: 'x', ext: '', mime: 'application/msword').typeLabel,
        'DOC',
      );
      expect(f(name: 'x', ext: '', mime: 'application/zip').typeLabel, 'FILE');
      expect(f(name: 'x', ext: '').typeLabel, 'FILE');
      expect(f(name: 'noext').typeLabel, 'FILE');
    });

    test('only plain letters and digits are drawn', () {
      expect(f(name: 'a', ext: 'p<d>f').typeLabel, 'PDF');
      expect(f(name: 'a', ext: '😀', mime: 'image/png').typeLabel, 'IMAGE');
      expect(f(name: 'a', ext: 'ü.é').typeLabel, 'FILE');
      expect(f(name: 'a.tar.gz').typeLabel, 'GZ');
      expect(f(name: 'a', ext: 'x' * 20).typeLabel, 'FILE');
    });

    test('size formats; 0 or missing is left out', () {
      expect(f(size: 980).metaText, 'PDF · 980 B');
      expect(f(size: 1536).metaText, 'PDF · 1.5 KB');
      expect(f(size: 5 * 1024 * 1024).metaText, 'PDF · 5.0 MB');
      expect(f(size: 0).metaText, 'PDF');
      expect(f(size: -1).metaText, 'PDF');
      expect(SvFile.formatSize(0), '');
    });

    test('preview header with every part', () {
      final at = DateTime(2026, 11, 24, 12).millisecondsSinceEpoch;
      final x = f(size: 52224, ext: 'pdf', at: at);
      expect(
        x.headerText(position: 1, total: 5),
        'PDF · 51 KB · Uploaded Nov 24, 2026 · 1 of 5',
      );
    });

    test('preview header with parts missing', () {
      final at = DateTime(2026, 1, 5, 12).millisecondsSinceEpoch;
      expect(f(size: 0).headerText(), 'PDF');
      expect(
        f(size: 980).headerText(position: 2, total: 2),
        'PDF · 980 B · 2 of 2',
      );
      expect(f(at: at).headerText(), 'PDF · Uploaded Jan 5, 2026');
      expect(
        f(name: 'x', ext: '').headerText(position: 1, total: 3),
        'FILE · 1 of 3',
      );
    });
  });

  group('open: cache and revalidation', () {
    test(
      'first read stores under the ETag; the request carries the token',
      () async {
        final r = _Rig();
        addTearDown(r.dispose);
        r.http.queue.add(_Reply(200, body: [1, 2, 3], etag: '"$_tag1"'));
        final got = await r.open(_file());
        expect(got.isMaybeStale, isFalse);
        expect(await got.file.readAsBytes(), [1, 2, 3]);
        expect(r.names, ['${_id}_$_tag1.pdf']);
        expect(
          r.http.seen.single.uri.toString(),
          'https://example.test/api/sd/files/$_id',
        );
        expect(r.header(0, 'Authorization'), 'Bearer TOKEN');
        expect(
          r.http.seen.single.headers.containsKey('If-None-Match'),
          isFalse,
        );
      },
    );

    test(
      'the next open always asks with If-None-Match; 304 shows the kept bytes',
      () async {
        final r = _Rig();
        addTearDown(r.dispose);
        r.http.queue
          ..add(_Reply(200, body: [1, 2, 3], etag: '"$_tag1"'))
          ..add(_Reply(304));
        await r.open(_file());
        final got = await r.open(_file());
        expect(r.http.seen.length, 2);
        expect(r.header(1, 'If-None-Match'), '"$_tag1"');
        expect(await got.file.readAsBytes(), [1, 2, 3]);
        expect(got.isMaybeStale, isFalse);
        expect(r.names, ['${_id}_$_tag1.pdf']);
      },
    );

    test(
      'a changed file is 200 with a new ETag: re-downloaded, old copy gone',
      () async {
        final r = _Rig();
        addTearDown(r.dispose);
        r.http.queue
          ..add(_Reply(200, body: [1], etag: '"$_tag1"'))
          ..add(_Reply(200, body: [9, 9], etag: '"$_tag2"'));
        await r.open(_file());
        final got = await r.open(_file());
        expect(await got.file.readAsBytes(), [9, 9]);
        expect(r.names, ['${_id}_$_tag2.pdf']);
      },
    );

    test('403 drops the kept copy and shows the server message', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue
        ..add(_Reply(200, body: [1], etag: '"$_tag1"'))
        ..add(
          _Reply(
            403,
            json: {
              'ok': false,
              'error': {'message': 'Not yours.'},
            },
          ),
        );
      await r.open(_file());
      final e = await r.fails(_file());
      expect(e.problem, SvFileProblem.forbidden);
      expect(e.message, 'Not yours.');
      expect(r.names, isEmpty);
    });

    test(
      '403 and 404 without a message use the fixed words; 404 drops the copy',
      () async {
        final r = _Rig();
        addTearDown(r.dispose);
        r.http.queue
          ..add(_Reply(200, body: [1], etag: '"$_tag1"'))
          ..add(_Reply(404))
          ..add(_Reply(403, body: utf8.encode('<html>no</html>')));
        await r.open(_file());
        final e404 = await r.fails(_file());
        expect(e404.problem, SvFileProblem.notFound);
        expect(e404.message, 'No such file.');
        expect(r.names, isEmpty);
        final e403 = await r.fails(_file());
        expect(e403.message, "That file isn't available to you.");
      },
    );

    test('401 asks to sign in again; 413 is too large', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue
        ..add(_Reply(401))
        ..add(_Reply(413));
      final e401 = await r.fails(_file());
      expect(e401.problem, SvFileProblem.unauthorized);
      expect(r.unauthorized, 1);
      expect((await r.fails(_file())).problem, SvFileProblem.tooLarge);
    });

    test(
      'a network failure keeps the copy and shows it as maybe out of date',
      () async {
        final r = _Rig();
        addTearDown(r.dispose);
        r.http.queue
          ..add(_Reply(200, body: [1, 2], etag: '"$_tag1"'))
          ..add(_Reply(0, error: DioExceptionType.connectionError));
        await r.open(_file());
        final got = await r.open(_file());
        expect(got.isMaybeStale, isTrue);
        expect(await got.file.readAsBytes(), [1, 2]);
        expect(r.names, ['${_id}_$_tag1.pdf']);
      },
    );

    test('a network failure with nothing kept is an error', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue.add(_Reply(0, error: DioExceptionType.connectionTimeout));
      expect((await r.fails(_file())).problem, SvFileProblem.network);
    });

    test(
      'a weak or missing ETag is shown but not kept for revalidation',
      () async {
        final r = _Rig();
        addTearDown(r.dispose);
        r.http.queue
          ..add(_Reply(200, body: [1], etag: 'W/"$_tag1"'))
          ..add(_Reply(200, body: [2]))
          ..add(_Reply(200, body: [3], etag: _tag1));
        for (var i = 0; i < 3; i++) {
          final got = await r.open(_file());
          expect(await got.file.readAsBytes(), [i + 1]);
        }
        expect(
          r.http.seen.every((o) => !o.headers.containsKey('If-None-Match')),
          isTrue,
        );
        expect(r.names, ['${_id}_u.pdf']);
      },
    );

    test('an unexpected 304 is an error', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue.add(_Reply(304));
      final e = await r.fails(_file());
      expect(e.problem, SvFileProblem.other);
      expect(r.names, isEmpty);
    });

    test('an empty body is an error and nothing is kept', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue.add(_Reply(200, etag: '"$_tag1"'));
      expect((await r.fails(_file())).message, 'The file came back empty.');
      expect(r.names, isEmpty);
    });

    test('a file over 10 MB is shown but not kept', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue.add(
        _Reply(
          200,
          body: List.filled(SvFileRepository.maxFileBytes + 1, 7),
          etag: '"$_tag1"',
        ),
      );
      final got = await r.open(_file());
      expect(got.file.lengthSync(), SvFileRepository.maxFileBytes + 1);
      expect(r.names, ['${_id}_u.pdf']);
    });

    test('at most the newest 24 files are kept', () async {
      final r = _Rig(files: 3);
      addTearDown(r.dispose);
      for (var i = 0; i < 5; i++) {
        r.http.queue.add(
          _Reply(
            200,
            body: [i + 1],
            etag: '"${'${i + 1}'.padLeft(2, '0') * 32}"',
          ),
        );
        await r.open(_file(_idN(i)));
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(r.names.length, 3);
      expect(r.names.any((n) => n.startsWith(_idN(4))), isTrue);
      expect(r.names.any((n) => n.startsWith(_idN(0))), isFalse);
      expect(SvFileRepository.maxCacheFiles, 24);
    });

    test('the folder stays within the byte limit, newest kept', () async {
      final r = _Rig(limit: 2500);
      addTearDown(r.dispose);
      for (var i = 0; i < 3; i++) {
        r.http.queue.add(
          _Reply(
            200,
            body: List.filled(1000, i),
            etag: '"${'${i + 1}'.padLeft(2, '0') * 32}"',
          ),
        );
        await r.open(_file(_idN(i)));
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      expect(r.names.length, 2);
      expect(r.names.any((n) => n.startsWith(_idN(0))), isFalse);
      expect(SvFileRepository.maxCacheBytes, 30 * 1024 * 1024);
    });

    test('sign out or another organisation clears everything', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue.add(_Reply(200, body: [1], etag: '"$_tag1"'));
      await r.open(_file());
      expect(r.names, isNotEmpty);
      r.store.switchTo(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(r.temp.existsSync(), isFalse);
    });

    test('two overlapping reads of the same file share one request', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.hold = Completer<void>();
      r.http.queue.add(_Reply(200, body: [1, 2], etag: '"$_tag1"'));
      final seenProgress = <double>[];
      final a = r.open(_file());
      final b = r.repo.fetch(
        _file(),
        onProgress: seenProgress.add,
        cancel: CancelToken(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      r.http.hold!.complete();
      final got = await Future.wait([a, b]);
      expect(r.http.seen.length, 1);
      expect(got[0].file.path, got[1].file.path);
      expect(seenProgress, isNotEmpty);
      r.http.queue.add(_Reply(304));
      await r.open(_file());
      expect(r.http.seen.length, 2);
    });

    test('a different file is its own request', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue
        ..add(_Reply(200, body: [1], etag: '"$_tag1"'))
        ..add(_Reply(200, body: [2], etag: '"$_tag2"'));
      await Future.wait([r.open(_file(_idN(1))), r.open(_file(_idN(2)))]);
      expect(r.http.seen.length, 2);
    });
  });

  group('link', () {
    test(
      'a signed url is returned; a null url means use the download',
      () async {
        final r = _Rig();
        addTearDown(r.dispose);
        r.http.queue
          ..add(
            _Reply(
              200,
              json: {
                'url': 'https://files.example/x?sig=1',
                'expiresIn': 60,
                'name': 'a',
                'size': 3,
                'mime': 'x',
                'etag': _tag1,
              },
            ),
          )
          ..add(_Reply(200, json: {'url': null, 'expiresIn': null}))
          ..add(_Reply(200, json: {'url': 'javascript:alert(1)'}));
        final link = await r.repo.link(_file());
        expect(link!.url, 'https://files.example/x?sig=1');
        expect(link.expiresIn, 60);
        expect(r.http.seen.first.uri.path, '/api/sd/files/$_id/link');
        expect(r.header(0, 'Authorization'), 'Bearer TOKEN');
        expect(await r.repo.link(_file()), isNull);
        expect(await r.repo.link(_file()), isNull);
      },
    );
  });

  group('the viewer', () {
    test('a stale copy is flagged on the load', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      r.http.queue
        ..add(_Reply(200, body: [1], etag: '"$_tag1"'))
        ..add(_Reply(0, error: DioExceptionType.connectionError));
      await r.open(_file());
      final c = SvFilePreviewController(files: [_file()], repo: r.repo);
      await c.ensure(c.loads[0]);
      expect(c.loads[0].phase.value, SvFilePhase.ready);
      expect(c.loads[0].isMaybeStale.value, isTrue);
    });
  });
}
