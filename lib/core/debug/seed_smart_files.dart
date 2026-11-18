import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

import '../../data/repositories/sv_file_repository.dart';
import '../../data/smart_view/sv_file.dart';

/// DEMO_MODE and `/debug/smartfiles` (before-release list in CLAUDE.md): the
/// files of the Leave request demo, served by a fake downloader with
/// simulated progress; one of them always fails. No server.
class SeedSmartFiles {
  SeedSmartFiles._();

  static const imageId = 'a00000000000000000000001';
  static const textId = 'a00000000000000000000002';
  static const bigTextId = 'a00000000000000000000003';
  static const pdfId = 'a00000000000000000000004';
  static const longId = 'a00000000000000000000005';
  static const zipId = 'a00000000000000000000006';
  static const failId = 'a00000000000000000000007';
  static const jpgId = 'a00000000000000000000009';
  static const badPdfId = 'a0000000000000000000000a';
  static const docxId = 'a0000000000000000000000b';
  static const pptxId = 'a0000000000000000000000c';
  static const jsonId = 'a0000000000000000000000d';
  static const binId = 'a0000000000000000000000e';
  static const audioId = 'a0000000000000000000000f';

  /// The id of a file in a hidden field: in the rows, in no column.
  static const hiddenId = 'a00000000000000000000008';

  static const files = <SvFile>[
    SvFile(id: imageId, name: 'site-photo.png', mime: 'image/png', size: 833),
    SvFile(id: textId, name: 'notes.txt', mime: 'text/plain', size: 1180),
    SvFile(
      id: bigTextId,
      name: 'export-log.csv',
      mime: 'text/csv',
      size: 262144,
    ),
    SvFile(
      id: pdfId,
      name: 'Medical certificate.pdf',
      mime: 'application/pdf',
      size: 1500,
    ),
    SvFile(
      id: longId,
      name:
          'Quarterly leave balance reconciliation for the whole department '
          'final version 2026.xlsx',
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      size: 1572864,
    ),
    SvFile(
      id: zipId,
      name: 'travel-documents.zip',
      mime: 'application/zip',
      size: 3145728,
    ),
    SvFile(
      id: failId,
      name: 'scan-damaged.jpg',
      mime: 'image/jpeg',
      size: 204800,
    ),
    SvFile(
      id: hiddenId,
      name: 'internal.pdf',
      mime: 'application/pdf',
      size: 900,
    ),
    SvFile(id: jpgId, name: 'receipt.jpg', mime: 'image/jpeg', size: 833),
    SvFile(
      id: badPdfId,
      name: 'Protected statement.pdf',
      mime: 'application/pdf',
      size: 400,
    ),
    SvFile(
      id: docxId,
      name: 'Leave policy.docx',
      mime:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      size: 2300,
    ),
    SvFile(
      id: pptxId,
      name: 'Handover plan.pptx',
      mime:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      size: 2900,
    ),
    SvFile(
      id: jsonId,
      name: 'balances.json',
      mime: 'application/json',
      size: 150,
    ),
    SvFile(
      id: binId,
      name: 'device-dump.bin',
      mime: 'application/octet-stream',
      size: 2048,
    ),
    SvFile(
      id: audioId,
      name: 'voice-note.wav',
      mime: 'audio/wav',
      size: 32044,
    ),
  ];

  static final _byId = {for (final f in files) f.id: f};

  /// The ids a demo record holds (none for every sixth).
  static List<String> idsFor(int i) => switch (i % 6) {
    0 => const [],
    1 => const [imageId, jsonId],
    2 => const [textId, pdfId],
    3 => const [longId, zipId, imageId, bigTextId, pdfId],
    4 => const [failId],
    _ => const [
      docxId,
      pptxId,
      audioId,
      badPdfId,
      binId,
      jpgId,
      pdfId,
    ],
  };

  /// The row's `files` map for [values]: field name to file details.
  static Map<String, dynamic> infoOf(Map<String, dynamic> values) => {
    for (final field in const ['attach', 'internal_files'])
      if (values[field] is List)
        field: [
          for (final id in values[field] as List)
            if (_byId['$id'] case final f?)
              {'id': f.id, 'name': f.name, 'mime': f.mime, 'size': f.size},
        ],
  };

  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAPAAAACgCAIAAAC9uXYyAAADCElEQVR42u3dwW3rMBBFUd'
    'WYdTpKa6on23EFQiKZNDkzh/D+Ak8H+MC3GB8/37+PP8fX+fijqzujexhaF2hD6wLtAesC'
    'rasLtC7QhtYF2tC6QHvAukDr6gKtC7ShdYE2tC7QurpA6+oCrQu0oXWBNrQu0Lq6QOvqXn'
    '6MpVuqa2hdoA2tC7QHrAu0ri7QukAbWhdoQ+sC7QHrAq2rC7Qu0IbWBdrQukDr6gKtqwu0'
    'LtCG1gXa0LpA6+oCrat72TWWrlvfhr78xP1jZ6D36sa4Y2egl3Vj5rEz0J/rxqcO0EDP7c'
    'aKAzTQ47ux+gAN9LBu7HGABnpAN3Y6QAP9vBu7HqCBvt2NvQ/QQN/oRoYDNNBnGc3/NA10'
    'd9CR7QANdB3Nf5oGui/oyHyABhpooOuCjvwHaKDraL4yDXQ70FHrdAft1cRioN36duskCp'
    'sGGmiggc4JOuoeoIEGGmgXXbc3DTTQQAMNNNBAL+xGjwM00EADDTTQQAMNNNCJ/5zXnhe0'
    'gAYaaKCBBhpooIEGGmiggQYaaKCBBhpooP1O4YRuK9BufQMNNNBAAw000EADDTTQQAMNNN'
    'BAAw000EADDTTQb3b7fE0INNBAAw000EADDTTQw7pN3rMDGmiggQYaaKCXdzu81w800EAD'
    'nfZ6T23NQAMNtN8p9DuFG7+84dY30EADnfyfs8Lv1gHdEXQN04V/jx3oJ92S7z0DDTTQQF'
    'f5L6F611KAbg06o+ny3xUA/W63jGaggc5kusm3uUCP6RbQDDTQOUy3et8G6MHdpJSBBnp3'
    '0z3fiAR6SjejZqCB3vHPiDV/Zx3oOhdsm+8MdJ3bLnYGell3kmM7A72+Owqxnf1Ooa7uCb'
    'Qu0IbWBdoD1gVaVxdoXaANrQu0oXWB9oB1gdbVBVoXaEPrAm1oXaA9YF2gdXWB1gXa0LpA'
    'G1oXaF1doHV1/U6hrlvfhtYF2tC6QOvqAq2rC7Qu0IbWBdrQukDr6gKtqwu0LtCG1gXa0L'
    'pA6+oCrasLtC7QhtYF2tC6QOvqAq3bvPsCs+ntG96I4dQAAAAASUVORK5CYII=',
  );

  static Uint8List _zipOf(Map<String, String> entries) {
    final zip = Archive();
    entries.forEach((n, t) => zip.addFile(ArchiveFile.string(n, t)));
    return Uint8List.fromList(ZipEncoder().encode(zip));
  }

  /// A valid PDF of [pages] pages (xref offsets computed).
  static Uint8List _pdf(int pages) {
    final objs = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [${[for (var i = 0; i < pages; i++) '${4 + i * 2} 0 R'].join(' ')}] /Count $pages >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    ];
    for (var i = 0; i < pages; i++) {
      final text = 'BT /F1 28 Tf 72 700 Td (Leave summary - page ${i + 1}) Tj ET';
      objs.add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents ${5 + i * 2} 0 R /Resources << /Font << /F1 3 0 R >> >> >>',
      );
      objs.add('<< /Length ${text.length} >>\nstream\n$text\nendstream');
    }
    final out = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objs.length; i++) {
      offsets.add(out.length);
      out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
    }
    final xref = out.length;
    out.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
    for (final o in offsets) {
      out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write(
      'trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF',
    );
    return Uint8List.fromList(latin1.encode(out.toString()));
  }

  /// A 2 s, 8 kHz, 16 bit mono sine as a WAV.
  static Uint8List _wav() {
    const rate = 8000;
    const n = rate * 2;
    final data = ByteData(44 + n * 2);
    void tag(int at, String t) {
      for (var i = 0; i < 4; i++) {
        data.setUint8(at + i, t.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    data.setUint32(4, 36 + n * 2, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    data.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      data.setInt16(
        44 + i * 2,
        (math.sin(2 * math.pi * 440 * i / rate) * 6000).round(),
        Endian.little,
      );
    }
    return data.buffer.asUint8List();
  }

  static Uint8List _docx() => _zipOf({
    '[Content_Types].xml': '<Types/>',
    'word/document.xml':
        '<w:document><w:body>'
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Leave policy</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Staff may take up to 24 days of paid leave a year.</w:t></w:r></w:p>'
        '<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Requests need manager approval.</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr><w:r><w:t>Submit 5 days ahead</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/></w:numPr></w:pPr><w:r><w:t>Attach a certificate for sick leave</w:t></w:r></w:p>'
        '</w:body></w:document>',
  });

  static Uint8List _pptx() => _zipOf({
    '[Content_Types].xml': '<Types/>',
    for (var i = 1; i <= 3; i++)
      'ppt/slides/slide$i.xml':
          '<p:sld><a:p><a:r><a:t>Handover - step $i</a:t></a:r></a:p>'
          '<a:p><a:r><a:t>Owner: Ana Rao</a:t></a:r></a:p>'
          '<a:p><a:r><a:t>Due in ${i * 2} days</a:t></a:r></a:p></p:sld>',
  });

  /// The demo bytes of [f] (what the fake downloader writes).
  static Uint8List bytesOf(SvFile f) {
    switch (f.id) {
      case imageId || jpgId:
        return _png;
      case textId:
        return utf8.encode(
          'Leave notes\n\nHanded over the weekly report to Rhea.\n'
                  'Phone stays on for anything urgent.\n' *
              20,
        );
      case bigTextId:
        final line = utf8.encode('2026-11-18,leave,approved,Ana Rao,3 days\n');
        final out = BytesBuilder();
        out.add(utf8.encode('Date,Type,Status,Name,Length\n'));
        while (out.length < f.size) {
          out.add(line);
        }
        return out.takeBytes();
      case pdfId:
        return _pdf(5);
      case badPdfId || hiddenId:
        return utf8.encode('%PDF-1.7\n/Encrypt << /Filter /Standard >>\n\u0000');
      case docxId:
        return _docx();
      case pptxId:
        return _pptx();
      case jsonId:
        return utf8.encode(
          '{"employee":"Ana Rao","balances":{"annual":12,"sick":4},"open":[1,2,3]}',
        );
      case audioId:
        return _wav();
      case zipId:
        return _zipOf({
          'itinerary.txt': 'Flight 7 Dec',
          'visa/form.pdf': 'x' * 900,
          'photos/passport.jpg': 'y' * 4000,
        });
      case binId:
        return Uint8List.fromList(List.generate(512, (i) => i % 251));
      default:
        return Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4, 5, 6]);
    }
  }

  /// Writes the demo bytes in five steps, 160 ms apart; the damaged scan
  /// fails after the second step.
  static Future<void> fetch(
    SvFile file,
    String targetPath,
    void Function(double progress) onProgress,
    CancelToken cancel, {
    Duration step = const Duration(milliseconds: 160),
  }) async {
    for (var n = 1; n <= 5; n++) {
      await Future<void>.delayed(step);
      if (cancel.isCancelled) {
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.cancel,
        );
      }
      if (file.id == failId && n == 3) {
        throw DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionError,
        );
      }
      onProgress(n / 5);
    }
    await File(targetPath).writeAsBytes(bytesOf(file));
  }

  static const SvFileFetcher fetcher = _fetch;

  static Future<void> _fetch(
    SvFile file,
    String targetPath,
    void Function(double) onProgress,
    CancelToken cancel,
  ) => fetch(file, targetPath, onProgress, cancel);
}
