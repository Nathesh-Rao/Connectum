import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectum/data/repositories/attachment_repository.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  RequestOptions? options;
  final body = <int>[];
  int status = 200;
  Object reply = {
    'ok': true,
    'data': {
      'file': {
        'id': 'f-1',
        'name': 'note.pdf',
        'mime': 'application/pdf',
        'size': 5,
        'by': 'ana',
        'ts': 1,
      },
    },
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.addAll(chunk);
      }
    }
    return ResponseBody.fromString(
      jsonEncode(reply),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Attachments extends Fake implements AttachmentRepository {
  _Attachments(this.dio);

  @override
  final Dio dio;
}

class _Session extends Fake implements SessionStore {
  @override
  String? get token => 'tok-1';
}

void main() {
  late _Adapter adapter;
  late FormFileRepository files;
  late Directory dir;

  setUp(() {
    adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    files = FormFileRepository(
      _Attachments(dio),
      _Session(),
      origin: 'https://dev.example.test/',
    );
    dir = Directory.systemTemp.createTempSync('record_files_test');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  PickedAttachment picked(
    String name,
    List<int> bytes, {
    String mime = 'application/pdf',
  }) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return PickedAttachment(
      kind: 'file',
      path: f.path,
      name: name,
      mime: mime,
      bytes: bytes.length,
    );
  }

  test(
    'the upload is raw bytes with the real mime, length and bearer token',
    () async {
      final progress = <double>[];
      final done = await files.upload(
        picked('note.pdf', [1, 2, 3, 4, 5]),
        onProgress: progress.add,
        cancel: CancelToken(),
      );
      final o = adapter.options!;
      expect(o.method, 'POST');
      expect(o.uri.path, '/api/sd/files');
      expect(o.uri.queryParameters, {'name': 'note.pdf'});
      expect(o.headers['Authorization'], 'Bearer tok-1');
      expect(o.headers[Headers.contentTypeHeader], 'application/pdf');
      expect(o.headers[Headers.contentLengthHeader], 5);
      expect(adapter.body, [1, 2, 3, 4, 5]);
      expect(done.id, 'f-1');
      expect(done.name, 'note.pdf');
      expect(done.size, 5);
    },
  );

  test('a record file never goes to the chat /upload endpoint', () async {
    await files.upload(
      picked('a.bin', [1], mime: 'application/octet-stream'),
      onProgress: (_) {},
      cancel: CancelToken(),
    );
    expect(adapter.options!.uri.path, isNot('/upload'));
    expect(adapter.options!.uri.path, '/api/sd/files');
  });

  test(
    'over 10 MB is refused before anything is sent, in friendly words',
    () async {
      final big = PickedAttachment(
        kind: 'file',
        path: '${dir.path}/none',
        name: 'big.bin',
        mime: 'application/octet-stream',
        bytes: 10 * 1024 * 1024 + 1,
      );
      await expectLater(
        files.upload(big, onProgress: (_) {}, cancel: CancelToken()),
        throwsA(
          isA<AttachmentException>().having(
            (e) => e.message,
            'message',
            'That file is over 10 MB. Choose a smaller one.',
          ),
        ),
      );
      expect(adapter.options, isNull);
    },
  );

  test(
    'just under 10 MB is sent (the limit is the record one, not the chat one)',
    () async {
      final size = 10 * 1024 * 1024 - 1;
      final p = picked(
        'large.bin',
        List.filled(size, 7),
        mime: 'application/octet-stream',
      );
      final done = await files.upload(
        p,
        onProgress: (_) {},
        cancel: CancelToken(),
      );
      expect(done.id, 'f-1');
      expect(adapter.body.length, size);
    },
  );

  test(
    'the temp copy is deleted after a good upload only when asked',
    () async {
      final keep = picked('keep.pdf', [1]);
      await files.upload(keep, onProgress: (_) {}, cancel: CancelToken());
      expect(File(keep.path).existsSync(), isTrue);
      // The test file lives in the system temp folder, like a picked copy.
      await files.upload(
        keep,
        onProgress: (_) {},
        cancel: CancelToken(),
        deleteAfter: true,
      );
      expect(File(keep.path).existsSync(), isFalse);
    },
  );

  test(
    'a server refusal is shown in its own words and is not retried',
    () async {
      adapter
        ..status = 400
        ..reply = {
          'ok': false,
          'error': {
            'code': 'invalid',
            'message': 'You can attach only files you uploaded yourself.',
          },
        };
      await expectLater(
        files.upload(
          picked('x.pdf', [1]),
          onProgress: (_) {},
          cancel: CancelToken(),
        ),
        throwsA(
          isA<AttachmentException>().having(
            (e) => e.message,
            'message',
            'You can attach only files you uploaded yourself.',
          ),
        ),
      );
    },
  );
}
