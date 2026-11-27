import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/data/smart_view/sv_file.dart';
import 'package:connectum/features/smart_view/sv_file_preview_controller.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_preview_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

// Fakes only: a chunked fake HTTP adapter and temp folders.

const _a = 'a00000000000000000000001';
const _b = 'b00000000000000000000002';
final _tag = 'c3' * 32;

SvFile _file(String id, {int size = 4000}) =>
    SvFile(id: id, name: 'Report $id.pdf', mime: 'application/pdf', size: size);

/// Answers each request with the chunks the test lets through one at a time.
class _Chunked implements HttpClientAdapter {
  final seen = <RequestOptions>[];
  final _gates = <String, StreamController<List<int>>>{};
  final _status = <String, int>{};
  final _length = <String, bool>{};
  final _etag = <String, bool>{};

  /// Opens the answer for [id] (called before the request is made).
  StreamController<List<int>> open(
    String id, {
    int status = 200,
    bool isLengthSent = true,
    bool isEtagSent = true,
  }) {
    _status[id] = status;
    _length[id] = isLengthSent;
    _etag[id] = isEtagSent;
    return _gates[id] = StreamController<List<int>>();
  }

  int total = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final id = options.uri.pathSegments.last;
    final gate = _gates[id]!;
    final status = _status[id]!;
    return ResponseBody(
      gate.stream.map((c) => Uint8List.fromList(c)),
      status,
      headers: {
        if (_etag[id]!) 'etag': ['"$_tag"'],
        if (_length[id]! && status == 200) 'content-length': ['$total'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Rig {
  _Rig() {
    temp = Directory.systemTemp.createTempSync('svp_temp');
    repo = SvFileRepository(
      dio: Dio()..httpClientAdapter = http,
      token: () => 'TOKEN',
      origin: 'https://example.test',
      cache: AttachmentCache(Dio()),
      onUnauthorized: () {},
      store: FakeStore(),
      tempDir: () async => temp..createSync(recursive: true),
    );
  }

  final http = _Chunked();
  late final Directory temp;
  late final SvFileRepository repo;

  SvFilePreviewController preview(List<SvFile> files, [int index = 0]) =>
      SvFilePreviewController(files: files, repo: repo, index: index);

  void dispose() {
    repo.dispose();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<int> _bytes(int n) => List<int>.filled(n, 7);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Rig rig;
  setUp(() => rig = _Rig());
  tearDown(() => rig.dispose());

  group('a first download', () {
    test('progress goes up to 100 and never back', () async {
      rig.http.total = 4000;
      final gate = rig.http.open(_a);
      final c = rig.preview([_file(_a)]);
      final l = c.loads[0];
      final seen = <int>[];
      final percents = <double>[];
      l.transfer.listen((t) => seen.add(t.received));
      l.progress.listen(percents.add);
      final done = c.ensure(l);
      await _settle();
      gate.add(_bytes(1000));
      await _settle();
      expect(l.transfer.value.text, '25% · 1.0 of 3.9 KB');
      gate.add(_bytes(1000));
      gate.add(_bytes(2000));
      await gate.close();
      expect(await done, isNotNull);
      expect(l.transfer.value.fraction, 1);
      expect(l.transfer.value.text, startsWith('100% · '));
      expect(seen, orderedEquals([...seen]..sort()));
      expect(percents.last, 1);
      expect(percents.every((p) => p <= 1), isTrue);
      expect(percents, orderedEquals([...percents]..sort()));
    });

    test('no content length: bytes only, never a percentage', () async {
      rig.http.total = 0;
      final gate = rig.http.open(_a, isLengthSent: false);
      final c = rig.preview([_file(_a, size: 0)]);
      final l = c.loads[0];
      final done = c.ensure(l);
      await _settle();
      gate.add(_bytes(2500));
      await _settle();
      expect(l.transfer.value.fraction, isNull);
      expect(l.transfer.value.text, '2.4 KB');
      expect(l.progress.value, 0);
      await gate.close();
      await done;
      expect(l.phase.value, SvFilePhase.ready);
    });

    test('a content length smaller than the bytes never passes 100', () {
      const t = SvFileProgress(5000, 4000);
      expect(t.fraction, 1);
      expect(t.text, startsWith('100% · '));
    });
  });

  group('no percentage', () {
    test('304 and a kept copy show nothing', () async {
      rig.http.total = 1000;
      final first = rig.http.open(_a)..add(_bytes(1000));
      unawaited(first.close());
      final c1 = rig.preview([_file(_a, size: 1000)]);
      await c1.ensure(c1.loads[0]);
      unawaited(rig.http.open(_a, status: 304).close());
      final c2 = rig.preview([_file(_a, size: 1000)]);
      final l = c2.loads[0];
      final seen = <SvFileProgress>[];
      final ups = <double>[];
      l.transfer.listen((t) {
        if (t.isStarted) seen.add(t);
      });
      l.progress.listen((p) {
        if (p > 0) ups.add(p);
      });
      await c2.ensure(l);
      expect(l.phase.value, SvFilePhase.ready);
      expect(seen, isEmpty);
      expect(ups, isEmpty);
      expect(l.transfer.value.isStarted, isFalse);
      expect(rig.http.seen.last.headers['If-None-Match'], '"$_tag"');
    });

    test('a 200 that replaces a kept copy does show progress', () async {
      rig.http.total = 1000;
      final first = rig.http.open(_a)..add(_bytes(1000));
      unawaited(first.close());
      final c1 = rig.preview([_file(_a, size: 1000)]);
      await c1.ensure(c1.loads[0]);
      rig.http.total = 2000;
      final gate = rig.http.open(_a);
      final c2 = rig.preview([_file(_a, size: 2000)]);
      final done = c2.ensure(c2.loads[0]);
      await _settle();
      gate.add(_bytes(1000));
      await _settle();
      expect(c2.loads[0].transfer.value.text, startsWith('50% · '));
      gate.add(_bytes(1000));
      await gate.close();
      await done;
    });
  });

  group('shared and per file', () {
    test(
      'two readers of one file share one request and one progress',
      () async {
        rig.http.total = 4000;
        final gate = rig.http.open(_a);
        final one = rig.preview([_file(_a)]);
        final two = rig.preview([_file(_a)]);
        final d1 = one.ensure(one.loads[0]);
        await _settle();
        gate.add(_bytes(1000));
        await _settle();
        final d2 = two.ensure(two.loads[0]);
        await _settle();
        expect(two.loads[0].transfer.value.received, 1000);
        gate.add(_bytes(1000));
        await _settle();
        expect(one.loads[0].transfer.value.received, 2000);
        expect(two.loads[0].transfer.value.received, 2000);
        gate.add(_bytes(2000));
        await gate.close();
        await Future.wait([d1, d2]);
        expect(rig.http.seen, hasLength(1));
        expect(two.loads[0].transfer.value.fraction, 1);
      },
    );

    test('swipe away and back keeps the progress', () async {
      rig.http.total = 4000;
      final gate = rig.http.open(_a);
      final c = rig.preview([_file(_a), _file(_b)]);
      final done = c.ensure(c.loads[0]);
      await _settle();
      gate.add(_bytes(1000));
      await _settle();
      c.onPage(1);
      c.onPage(0);
      await _settle();
      expect(c.loads[0].phase.value, SvFilePhase.loading);
      expect(c.loads[0].transfer.value.received, 1000);
      gate.add(_bytes(3000));
      await gate.close();
      await done;
      expect(rig.http.seen.where((o) => o.uri.path.endsWith(_a)), hasLength(1));
    });

    test('progress of one file never shows on another', () async {
      rig.http.total = 4000;
      final ga = rig.http.open(_a);
      final gb = rig.http.open(_b);
      final c = rig.preview([_file(_a), _file(_b)]);
      final da = c.ensure(c.loads[0]);
      final db = c.ensure(c.loads[1]);
      await _settle();
      ga.add(_bytes(3000));
      gb.add(_bytes(500));
      await _settle();
      expect(c.loads[0].transfer.value.received, 3000);
      expect(c.loads[1].transfer.value.received, 500);
      ga.add(_bytes(1000));
      await ga.close();
      await da;
      expect(c.loads[1].transfer.value.received, 500);
      gb.add(_bytes(3500));
      await gb.close();
      await db;
    });

    test('a cancelled attempt cannot move a retried one', () async {
      rig.http.total = 4000;
      final g1 = rig.http.open(_a);
      final c = rig.preview([_file(_a)]);
      final l = c.loads[0];
      final first = c.ensure(l);
      await _settle();
      g1.add(_bytes(2000));
      await _settle();
      c.cancel();
      await g1.close();
      await first;
      expect(l.phase.value, anyOf(SvFilePhase.idle, SvFilePhase.error));
      final g2 = rig.http.open(_a);
      final second = c.ensure(l);
      await _settle();
      expect(l.transfer.value.received, 0);
      g2.add(_bytes(1000));
      await _settle();
      expect(l.transfer.value.received, 1000);
      g2.add(_bytes(3000));
      await g2.close();
      await second;
    });
  });

  group('the dialog', () {
    testWidgets('fits 320 px at text scale 1.5, with and without a length', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = rig.preview([_file(_a, size: 5 * 1024 * 1024)]);
      final l = c.loads[0];
      l.cancel = CancelToken();
      l.phase.value = SvFilePhase.loading;
      l.transfer.value = const SvFileProgress(2200000, 5 * 1024 * 1024);
      l.progress.value = l.transfer.value.fraction!;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.5),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: SvFilePreviewBody(controller: c),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('41% · 2.1 of 5.0 MB'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);

      l.transfer.value = const SvFileProgress(2200000);
      l.progress.value = 0;
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('2.1 MB'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
