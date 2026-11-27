import 'package:connectum/core/utils/attachment_tag.dart';
import 'package:connectum/features/conversation/models/document_info.dart';
import 'package:connectum/features/conversation/widgets/document_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _tag = AttachmentTag(
  kind: 'file',
  name: 'report.pdf',
  size: '2.4 MB',
  url: '/uploads/abc.pdf',
  type: 'application/pdf',
);

void main() {
  var taps = <String>[];

  Future<void> pump(
    WidgetTester t,
    DocumentButtonState state, {
    double progress = 0,
    double scale = 1,
    double width = 390,
  }) async {
    taps = [];
    t.view.physicalSize = Size(width, 800);
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
        home: Scaffold(
          body: Center(
            child: DocumentCard(
              tag: _tag,
              state: state,
              progress: progress,
              onDownload: () => taps.add('download'),
              onOpen: () => taps.add('open'),
              onCancel: () => taps.add('cancel'),
              onShare: () => taps.add('share'),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
  }

  final download = find.byIcon(Icons.file_download_outlined);
  final retry = find.byIcon(Icons.refresh);

  testWidgets('downloaded: no Open, no chip, the card opens the file', (
    t,
  ) async {
    await pump(t, DocumentButtonState.done);
    expect(find.text('Open'), findsNothing);
    expect(download, findsNothing);
    expect(retry, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
    await t.tap(find.text('report.pdf'));
    expect(taps, ['open']);
  });

  testWidgets('own sent file maps to the same chip-less card', (t) async {
    expect(
      DocumentButtonState.of(isSaved: true, download: null),
      DocumentButtonState.done,
    );
    await pump(t, DocumentButtonState.done);
    expect(find.text('Open'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('not downloaded: the download chip, tap downloads', (t) async {
    await pump(t, DocumentButtonState.idle);
    expect(download, findsOneWidget);
    await t.tap(download);
    expect(taps, ['download']);
  });

  testWidgets('downloading: the progress ring with the percentage', (t) async {
    await pump(t, DocumentButtonState.downloading, progress: 0.4);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
    await t.tap(find.text('40%'));
    expect(taps, ['cancel']);
  });

  testWidgets('failed: the retry chip', (t) async {
    await pump(t, DocumentButtonState.failed);
    expect(retry, findsOneWidget);
    await t.tap(retry);
    expect(taps, ['download']);
  });

  testWidgets('every state fits 320 px at 1.5x text', (t) async {
    for (final s in DocumentButtonState.values) {
      await pump(t, s, progress: 0.5, scale: 1.5, width: 320);
      expect(t.takeException(), isNull, reason: s.name);
    }
  });
}
