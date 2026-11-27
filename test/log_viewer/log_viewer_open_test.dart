import 'dart:io';

import 'package:connectum/core/log/app_log.dart';
import 'package:connectum/core/log/log_file_sink.dart';
import 'package:connectum/core/routes/app_pages.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/features/log_viewer/log_viewer_controller.dart';
import 'package:connectum/features/log_viewer/models/log_document.dart';
import 'package:connectum/features/settings/logs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Sink extends LogFileSink {
  _Sink(this.file) : super(directory: () async => Directory.systemTemp);

  final File? file;

  @override
  Future<File?> fileForExport() async => file;

  @override
  Future<void> flush() async {}
}

Future<void> _tap(WidgetTester tester, {required bool isRegistered}) async {
  Get.testMode = true;
  addTearDown(Get.reset);
  addTearDown(() => AppLog.file = null);
  final sink = _Sink(null);
  if (isRegistered) Get.put<LogFileSink>(sink);
  final logs = LogsController(sink: sink);
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(
      initialRoute: '/start',
      getPages: [
        GetPage<dynamic>(
          name: '/start',
          page: () => Scaffold(
            body: TextButton(
              onPressed: logs.openViewer,
              child: const Text('open'),
            ),
          ),
        ),
        ...AppPages.build(isRelease: false),
      ],
      builder: (c, child) => AppNoticeHost(child: child!),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final isRegistered in [true, false]) {
    testWidgets('openViewer sink registered=$isRegistered', (tester) async {
      await _tap(tester, isRegistered: isRegistered);
      expect(tester.takeException(), isNull);
      expect(Get.currentRoute, AppRoutes.logViewer);
      expect(find.text('No log entries yet'), findsOneWidget);
      expect(Get.isRegistered<LogViewerController>(), isTrue);
    });
  }

  group('reader inputs', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('logdoc'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('missing file', () async {
      await expectLater(
        const LogTextReader().read(File('${dir.path}/none.txt')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('empty, lines, over 2 MB', () async {
      final empty = File('${dir.path}/e.txt')..writeAsStringSync('');
      expect((await const LogTextReader().read(empty)).isEmpty, isTrue);

      final some = File('${dir.path}/s.txt')
        ..writeAsStringSync('10:00:01.000  I  APP  x\n10:00:02.000  E  A  y\n');
      final d = await const LogTextReader().read(some);
      expect(d.lines.length, 2);
      expect(d.kindOf(1), LogLineKind.error);
      final r = await const LogTextReader().search(d, 'x');
      expect(r.hits.length, 1);

      final big = File('${dir.path}/b.txt')
        ..writeAsStringSync(
          List.generate(
            60000,
            (i) => '10:00:01.000  I  APP  line $i padding',
          ).join('\n'),
        );
      expect(big.lengthSync(), greaterThan(LogDocument.maxBytes));
      final b = await const LogTextReader().read(big);
      expect(b.isPartial, isTrue);
      expect(b.lines, isNotEmpty);
    });
  });
}
