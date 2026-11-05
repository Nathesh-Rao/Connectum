import 'package:connectum/core/utils/attachment_tag.dart';
import 'package:connectum/features/conversation/models/document_info.dart';
import 'package:connectum/features/conversation/models/file_download.dart';
import 'package:flutter_test/flutter_test.dart';

AttachmentTag tag(String name, {String type = '', String size = ''}) =>
    AttachmentTag(
      kind: 'file',
      name: name,
      size: size,
      url: '/uploads/x',
      type: type,
    );

void main() {
  test('kind comes from the extension, then the MIME type', () {
    DocumentKind kind(String n, [String t = '']) => DocumentKind.of(n, t);
    expect(kind('a.PDF'), DocumentKind.pdf);
    expect(kind('a.docx'), DocumentKind.word);
    expect(kind('a.xlsx'), DocumentKind.excel);
    expect(kind('a.pptx'), DocumentKind.slides);
    expect(kind('a.txt'), DocumentKind.text);
    expect(kind('a.zip'), DocumentKind.archive);
    expect(kind('noext', 'application/pdf'), DocumentKind.pdf);
    expect(
      kind(
        'x',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      DocumentKind.excel,
    );
    expect(kind('a.bin', 'application/octet-stream'), DocumentKind.other);
    expect(kind('a.bin'), DocumentKind.other);
  });

  test('info line is "KIND · size", the kind alone without a size', () {
    expect(
      DocumentInfo.of(tag('r.pdf', size: '2.4 MB')).details,
      'PDF · 2.4 MB',
    );
    expect(
      DocumentInfo.of(tag('r.docx', size: '86 KB')).details,
      'DOC · 86 KB',
    );
    expect(DocumentInfo.of(tag('r.zip')).details, 'ZIP');
    expect(DocumentInfo.of(tag('r.dwg', size: '1 KB')).tileLabel, 'DWG');
    expect(DocumentInfo.of(tag('')).name, 'File');
  });

  test('long names are cut in the middle and keep the extension', () {
    const long = 'Quarterly financial statements for the board 2026.pdf';
    final short = DocumentInfo.middleEllipsis(long, DocumentInfo.maxNameChars);
    expect(short.length, DocumentInfo.maxNameChars);
    expect(short, contains('…'));
    expect(short.endsWith('.pdf'), isTrue);
    expect(short.startsWith('Quarterly'), isTrue);
    expect(DocumentInfo.middleEllipsis('a.pdf', 32), 'a.pdf');
  });

  test('button state: idle -> downloading -> done / failed / cancelled', () {
    DocumentButtonState of({required bool isSaved, FileDownload? d}) =>
        DocumentButtonState.of(isSaved: isSaved, download: d);
    expect(of(isSaved: false), DocumentButtonState.idle);
    final d = FileDownload();
    expect(of(isSaved: false, d: d), DocumentButtonState.downloading);
    d.isFailed.value = true;
    expect(of(isSaved: false, d: d), DocumentButtonState.failed);
    expect(of(isSaved: true), DocumentButtonState.done);
    // Cancelled: the controller removes the download, back to idle.
    expect(of(isSaved: false), DocumentButtonState.idle);
  });
}
