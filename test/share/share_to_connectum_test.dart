import 'dart:io';

import 'package:connectum/core/debug/seed_smart_files.dart';
import 'package:connectum/core/log/log_file_sink.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/models/pending_upload.dart';
import 'package:connectum/data/repositories/attachment_repository.dart';
import 'package:connectum/data/repositories/attachment_sender.dart';
import 'package:connectum/data/repositories/conversation_repository.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/repositories/share_repository.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/features/settings/logs_controller.dart';
import 'package:connectum/features/share/share_to_connectum_sheet.dart';
import 'package:connectum/features/smart_view/sv_file_preview_controller.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_preview_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';

// Fakes only: no server, no socket, no phone.

class _Conversations extends Fake implements ConversationRepository {
  _Conversations(List<Conversation> list) {
    conversations.assignAll(list);
  }

  @override
  final conversations = <Conversation>[].obs;

  @override
  final loadError = RxnString();

  Completer0? hold;
  bool shouldFail = false;
  int reloads = 0;

  @override
  Future<void> reload() async {
    reloads++;
    await hold?.future;
    loadError.value = shouldFail ? 'Could not read your chats.' : null;
  }
}

class Completer0 {
  final _c = Future<void>.delayed(const Duration(milliseconds: 3000));
  Future<void> get future => _c;
}

class _Messages extends Fake implements MessageRepository {
  final texts = <(String, String)>[];

  @override
  String lastBlock = '';

  @override
  Future<SendResult> sendText(
    String convId,
    String text, {
    String? replyTo,
  }) async {
    texts.add((convId, text));
    return SendResult.queued;
  }
}

/// Records one send per file and chat; a chat in [failing] refuses.
class _Sender extends Fake implements AttachmentSender {
  _Sender(this.messages);

  @override
  final _Messages messages;

  final sent = <(String, String)>[];
  final failing = <String, AttachmentException>{};
  final uploadedBefore = <String, bool>{};

  @override
  Future<void> send(PendingUpload upload, String convId) async {
    uploadedBefore[convId] = upload.uploaded != null;
    final e = failing[convId];
    if (e != null) throw e;
    upload.uploaded = const UploadedFile(url: '/uploads/a.pdf', type: 'x');
    sent.add((convId, upload.file.name));
  }
}

class _Attachments extends Fake implements AttachmentRepository {
  @override
  Future<PickedAttachment> describeFile(String path, String name) async {
    if (name.endsWith('.mp4') || name.endsWith('.svg')) {
      throw const AttachmentException(
        'Only PDF, Word, Excel, PowerPoint (.docx, .xlsx, .pptx) or text files can be sent.',
        isRetryable: false,
      );
    }
    return PickedAttachment(
      kind: 'file',
      path: path,
      name: name,
      mime: 'application/pdf',
      bytes: 10,
    );
  }
}

Conversation _chat(String id, String title, {int ts = 0, String? kind}) =>
    Conversation(
      convId: id,
      kind: kind ?? (id.startsWith('dm:') ? 'dm' : 'group'),
      title: title,
      lastTs: ts,
    );

class _Rig {
  _Rig({List<Conversation>? chats})
    : conversations = _Conversations(
        chats ??
            [
              _chat('dm:ana', 'Ana Lopez', ts: 3),
              _chat('group:ops', 'Ops team', ts: 5),
              _chat('dm:ben', 'Ben Cho', ts: 1),
              _chat('host:hq', 'Head office', ts: 9, kind: 'host'),
            ],
      ) {
    messages = _Messages();
    sender = _Sender(messages);
    socket = FakeSocket()..goOnline();
    repo = ShareRepository(
      conversations: conversations,
      sender: sender,
      attachments: _Attachments(),
      socket: socket,
    );
  }

  final _Conversations conversations;
  late final _Messages messages;
  late final _Sender sender;
  late final FakeSocket socket;
  late final ShareRepository repo;
}

const _file = ShareFile(name: 'Report.pdf', path: '/tmp/Report.pdf');

Future<void> _open(
  WidgetTester tester,
  _Rig rig, {
  Size size = const Size(360, 700),
  double textScale = 1,
  List<ShareFile> files = const [_file],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: AppNoticeHost(child: child!),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showShareToConnectum(
                context,
                repository: rig.repo,
                files: files,
              ),
              child: const Text('open picker'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open picker'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

Finder get _send => find.byKey(const ValueKey('share-send'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('picker', () {
    testWidgets('lists chats recent first; disabled ones are dimmed with why', (
      tester,
    ) async {
      final rig = _Rig();
      await _open(tester, rig);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Share to Connectum'), findsOneWidget);
      expect(find.text('Report.pdf'), findsOneWidget);
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('Head office'), lessThan(y('Ops team')));
      expect(y('Ops team'), lessThan(y('Ana Lopez')));
      expect(y('Ana Lopez'), lessThan(y('Ben Cho')));
      expect(find.text(ShareRepository.noFilesReason), findsOneWidget);
      await tester.tap(find.text('Head office'));
      await tester.pump();
      expect(find.byKey(const ValueKey('share-check')), findsNothing);
      expect(tester.widget<Text>(find.text('Send')).data, 'Send');
    });

    testWidgets('search filters; multi-select shows chips and the count', (
      tester,
    ) async {
      final rig = _Rig();
      await _open(tester, rig);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'ben');
      await tester.pump();
      expect(find.text('Ben Cho'), findsOneWidget);
      expect(find.text('Ana Lopez'), findsNothing);
      await tester.tap(find.text('Ben Cho'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.tap(find.text('Ops team'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Send to 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-check')), findsNWidgets(2));
      Finder chip(String name) => find.descendant(
        of: find.byKey(const ValueKey('share-chips')),
        matching: find.text(name),
      );
      expect(chip('Ben Cho'), findsOneWidget);
      expect(chip('Ops team'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('share-list')),
        const Offset(0, -200),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Ben Cho').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Send to 1'), findsOneWidget);
    });

    testWidgets('Send is disabled and sends nothing with no one chosen', (
      tester,
    ) async {
      final rig = _Rig();
      await _open(tester, rig);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_send, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(rig.sender.sent, isEmpty);
      expect(find.text('Share to Connectum'), findsOneWidget);
    });

    testWidgets('loading skeleton, then empty', (tester) async {
      final rig = _Rig(chats: []);
      rig.conversations.hold = Completer0();
      await _open(tester, rig);
      expect(find.byKey(const ValueKey('share-skeleton')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('No chats yet'), findsOneWidget);
    });

    testWidgets('error with retry', (tester) async {
      final rig = _Rig();
      rig.conversations.shouldFail = true;
      await _open(tester, rig);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Retry'), findsOneWidget);
      rig.conversations.shouldFail = false;
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ana Lopez'), findsOneWidget);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('fits 320 px at text scale $scale with chips and a note', (
        tester,
      ) async {
        final rig = _Rig();
        await _open(
          tester,
          rig,
          size: const Size(320, 640),
          textScale: scale,
          files: const [
            ShareFile(
              name: 'A very long report name for the quarter 2026.pdf',
              path: '/tmp/x.pdf',
            ),
          ],
        );
        await tester.pump(const Duration(milliseconds: 300));
        final list = tester.getRect(find.byKey(const ValueKey('share-list')));
        expect(list.height, greaterThan(120));
        await tester.drag(
          find.byKey(const ValueKey('share-list')),
          const Offset(0, -140),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Ops team'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Send to 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Send closes the sheet, stays on the page, one send each', (
      tester,
    ) async {
      final rig = _Rig();
      await _open(tester, rig);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ana Lopez'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ops team'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('share-add-note')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('share-caption')),
        'FYI',
      );
      await tester.tap(_send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(ShareToConnectumSheet), findsNothing);
      expect(find.text('open picker'), findsOneWidget);
      expect(rig.sender.sent.map((e) => e.$1).toSet(), {'dm:ana', 'group:ops'});
      expect(rig.sender.sent, hasLength(2));
      expect(rig.messages.texts, hasLength(2));
      expect(find.text('Shared with 2 chats'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a failing chat gives the partial notice and Retry', (
      tester,
    ) async {
      final rig = _Rig();
      rig.sender.failing['group:ops'] = const AttachmentException('Nope');
      await _open(tester, rig);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ana Lopez'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ops team'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Shared with 1 chat, 1 failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      rig.sender.failing.clear();
      rig.sender.sent.clear();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(rig.sender.sent, [('group:ops', 'Report.pdf')]);
      expect(find.text('Shared with 1 chat'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('offline keeps the sheet open and sends nothing', (
      tester,
    ) async {
      final rig = _Rig();
      rig.socket.goOffline();
      await _open(tester, rig);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ana Lopez'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_send);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sharing needs a connection.'), findsOneWidget);
      expect(find.byType(ShareToConnectumSheet), findsOneWidget);
      expect(rig.sender.sent, isEmpty);
    });

    testWidgets('a type chats refuse is told, not sent', (tester) async {
      final rig = _Rig();
      await _open(
        tester,
        rig,
        files: const [ShareFile(name: 'clip.mp4', path: '/tmp/clip.mp4')],
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Ana Lopez'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_send);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Only PDF, Word'), findsOneWidget);
      expect(find.byType(ShareToConnectumSheet), findsOneWidget);
      expect(rig.sender.sent, isEmpty);
    });
  });

  group('ShareRepository', () {
    test('a plain upload is made once and reused for the next chat', () async {
      final rig = _Rig();
      final file = PickedAttachment(
        kind: 'file',
        path: '/tmp/a.pdf',
        name: 'a.pdf',
        mime: 'application/pdf',
        bytes: 1,
      );
      final results = await rig.repo.send(
        files: [file],
        chats: [_chat('dm:ana', 'Ana'), _chat('dm:ben', 'Ben')],
      );
      expect(results.every((r) => r.isOk), isTrue);
      expect(rig.sender.uploadedBefore, {'dm:ana': false, 'dm:ben': true});
    });

    test('targets: only direct messages and groups are enabled', () async {
      final rig = _Rig();
      final t = await rig.repo.loadTargets();
      expect(
        {for (final x in t) x.chat.convId: x.isEnabled},
        {'host:hq': false, 'group:ops': true, 'dm:ana': true, 'dm:ben': true},
      );
    });
  });

  group('chat rules apply to a shared file', () {
    late Directory dir;
    late AttachmentRepository repo;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('share_rules');
      repo = AttachmentRepository(FakeStore());
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String name, List<int> bytes) {
      final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
      return f.path;
    }

    Future<Object?> run(String name, List<int> bytes) async {
      try {
        return await repo.describeFile(write(name, bytes), name);
      } on AttachmentException catch (e) {
        return e;
      }
    }

    test(
      'pdf, txt and png pass; html, svg, xml, mp4, csv, zip do not',
      () async {
        expect(
          await run('a.pdf', [0x25, 0x50, 0x44, 0x46, 0x2D, 1]),
          isA<PickedAttachment>(),
        );
        expect(await run('a.txt', [104, 105]), isA<PickedAttachment>());
        expect(
          await run('a.png', [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
          isA<PickedAttachment>().having((p) => p.kind, 'kind', 'image'),
        );
        for (final n in [
          'a.html',
          'a.svg',
          'a.xml',
          'a.mp4',
          'a.csv',
          'a.zip',
          'a.doc',
        ]) {
          expect(
            await run(n, [60, 104]),
            isA<AttachmentException>(),
            reason: n,
          );
        }
      },
    );

    test('a file that only claims to be a pdf is refused', () async {
      expect(await run('a.pdf', [1, 2, 3]), isA<AttachmentException>());
    });

    test('a file over the size limit is refused', () async {
      final big = List<int>.filled(AttachmentRepository.maxBlobBytes + 1, 65);
      expect(await run('a.txt', big), isA<AttachmentException>());
    });
  });

  group('preview dialog', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('share_prev'));
    tearDown(() => temp.deleteSync(recursive: true));

    SvFilePreviewController controller(ShareRepository? share) {
      final repo = SvFileRepository(
        dio: Dio(),
        token: () => null,
        origin: '',
        cache: AttachmentCache(Dio()),
        onUnauthorized: () {},
        fetcher: (f, path, etag, onProgress, cancel) async {
          await SeedSmartFiles.fetch(
            f,
            path,
            onProgress,
            cancel,
            step: Duration.zero,
          );
          return const SvFileReply(200);
        },
        tempDir: () async => temp..createSync(recursive: true),
        connectumShare: share,
      );
      return SvFilePreviewController(
        files: [SeedSmartFiles.files[3]],
        repo: repo,
      );
    }

    Future<void> pump(
      WidgetTester tester,
      SvFilePreviewController c, {
      double scale = 1,
    }) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: AppNoticeHost(child: child!),
          ),
          home: SvFilePreviewBody(controller: c),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final scale in [1.0, 1.5]) {
      testWidgets('three buttons at 320 px, text scale $scale', (tester) async {
        final c = controller(_Rig().repo);
        await pump(tester, c, scale: scale);
        final share = find.byKey(const ValueKey('sv-file-share-connectum'));
        final down = find.byKey(const ValueKey('sv-file-download'));
        final open = find.byKey(const ValueKey('sv-file-open'));
        expect(share, findsOneWidget);
        expect(find.text('Share to Connectum'), findsOneWidget);
        final s = tester.getRect(share);
        final d = tester.getRect(down);
        final o = tester.getRect(open);
        expect(d.top, greaterThan(s.bottom));
        expect(o.top, d.top);
        expect((d.width - o.width).abs(), lessThan(1));
        expect(s.width, greaterThan(d.width * 1.8));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no sharing set up: the two buttons only', (tester) async {
      final c = controller(null);
      await pump(tester, c);
      expect(find.text('Share to Connectum'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Open with…'), findsOneWidget);
    });

    testWidgets('tap opens the picker with the file name, no navigation', (
      tester,
    ) async {
      final c = controller(_Rig().repo);
      await tester.runAsync(() => c.ensure(c.current));
      await pump(tester, c);
      await tester.tap(find.text('Share to Connectum'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ShareToConnectumSheet), findsOneWidget);
      expect(find.byType(SvFilePreviewBody), findsOneWidget);
      expect(find.text(SeedSmartFiles.files[3].name), findsWidgets);
    });
  });

  group('logs', () {
    testWidgets('Share to Connectum opens the picker with the log file', (
      tester,
    ) async {
      late Directory dir;
      late LogFileSink sink;
      late LogsController c;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('logshare');
        sink = LogFileSink(
          directory: () async => dir,
          flushInterval: const Duration(hours: 1),
        );
        await sink.init();
        await sink.startNew();
        c = LogsController(sink: sink, connectumShare: _Rig().repo);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => c.shareToConnectum(context),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('go'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ShareToConnectumSheet), findsOneWidget);
      expect(find.textContaining('ConnectumMobileLog_'), findsOneWidget);
      await tester.runAsync(() async {
        c.dispose();
        await dir.delete(recursive: true);
      });
    });
  });
}
