import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One sheet of a spreadsheet: the rows as text, the first row being the
/// header. [isCut] when rows or columns were left out by the caps.
class SvSheetTable {
  const SvSheetTable({
    required this.name,
    required this.rows,
    this.isCut = false,
    this.totalRows = 0,
  });

  final String name;
  final List<List<String>> rows;
  final bool isCut;
  final int totalRows;

  int get columns => rows.fold(0, (m, r) => r.length > m ? r.length : m);
}

class SvSheetBook {
  const SvSheetBook(this.tables);

  final List<SvSheetTable> tables;
}

enum SvBlockStyle { normal, heading, list }

class SvDocBlock {
  const SvDocBlock(
    this.text, {
    this.style = SvBlockStyle.normal,
    this.isBold = false,
  });

  final String text;
  final SvBlockStyle style;
  final bool isBold;
}

/// The text of a Word file (one page) or a slide deck (a page per slide).
class SvDocText {
  const SvDocText({required this.isSlides, required this.pages});

  final bool isSlides;
  final List<List<SvDocBlock>> pages;
}

class SvZipEntry {
  const SvZipEntry(this.name, this.size);

  final String name;
  final int size;
}

class SvZipListing {
  const SvZipListing({
    required this.entries,
    required this.totalFiles,
    required this.totalSize,
  });

  final List<SvZipEntry> entries;
  final int totalFiles;
  final int totalSize;
}

/// Pure functions behind the file viewers. Safe to run in an isolate.
class SvPreviewParsers {
  SvPreviewParsers._();

  static const maxRows = 500;
  static const maxColumns = 50;
  static const maxParagraphs = 3000;
  static const maxZipEntries = 500;
  static const maxEntryBytes = 8 * 1024 * 1024;
  static const maxJsonPretty = 200 * 1024;

  /// Pretty JSON when [text] is valid JSON under 200 KB, else null.
  static String? prettyJson(String text) {
    if (text.length > maxJsonPretty) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty || (trimmed[0] != '{' && trimmed[0] != '[')) {
      return null;
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
    } on FormatException {
      return null;
    }
  }

  static SvSheetTable parseCsvText(String text) => parseCsv(text);

  static SvSheetTable parseCsvBytes(List<int> bytes) =>
      parseCsv(utf8.decode(bytes, allowMalformed: true));

  /// A tolerant CSV / TSV parser: quotes with doubled quotes, embedded
  /// newlines, and the delimiter (comma, semicolon or tab) taken from the
  /// first line. Rows and columns are capped.
  static SvSheetTable parseCsv(String text, {String name = 'Sheet 1'}) {
    var src = text.startsWith('﻿') ? text.substring(1) : text;
    final delimiter = _delimiter(src);
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    var isCut = false;
    var total = 0;

    void endCell() {
      if (row.length < maxColumns) {
        row.add(cell.toString());
      } else {
        isCut = true;
      }
      cell.clear();
    }

    void endRow() {
      endCell();
      total++;
      if (rows.length < maxRows) {
        rows.add(row);
      } else {
        isCut = true;
      }
      row = <String>[];
    }

    var i = 0;
    var hasContent = false;
    while (i < src.length) {
      final ch = src[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < src.length && src[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"' && cell.isEmpty) {
        inQuotes = true;
        hasContent = true;
      } else if (ch == delimiter) {
        endCell();
        hasContent = true;
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < src.length && src[i + 1] == '\n') i++;
        if (hasContent || cell.isNotEmpty || row.isNotEmpty) endRow();
        hasContent = false;
      } else {
        cell.write(ch);
        hasContent = true;
      }
      i++;
    }
    if (hasContent || cell.isNotEmpty || row.isNotEmpty) endRow();
    return SvSheetTable(name: name, rows: rows, isCut: isCut, totalRows: total);
  }

  static String _delimiter(String src) {
    var inQuotes = false;
    final counts = {',': 0, ';': 0, '\t': 0};
    for (var i = 0; i < src.length; i++) {
      final ch = src[i];
      if (ch == '"') inQuotes = !inQuotes;
      if (inQuotes) continue;
      if (ch == '\n') break;
      if (counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
    }
    var best = ',';
    var n = 0;
    counts.forEach((k, v) {
      if (v > n) {
        best = k;
        n = v;
      }
    });
    return best;
  }

  static String _unescape(String s) => s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
        return String.fromCharCode(int.parse(m[1]!, radix: 16));
      })
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (m) => String.fromCharCode(int.parse(m[1]!)),
      )
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static String? _entryText(Archive zip, String name) {
    for (final f in zip.files) {
      if (f.isFile && f.name == name && f.size <= maxEntryBytes) {
        return utf8.decode(f.content, allowMalformed: true);
      }
    }
    return null;
  }

  /// The paragraphs of `word/document.xml` as plain text with headings, bold
  /// and list items marked. No images, no table layout. Null when [bytes] is
  /// not a Word file.
  static SvDocText? parseDocx(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } on Object {
      return null;
    }
    if (zip.files.isEmpty) return null;
    final xml = _entryText(zip, 'word/document.xml');
    if (xml == null) return null;
    final blocks = <SvDocBlock>[];
    for (final p in RegExp(
      r'<w:p[ >].*?</w:p>',
      dotAll: true,
    ).allMatches(xml)) {
      final para = p.group(0)!;
      final runs = RegExp(r'<w:r[ >].*?</w:r>', dotAll: true).allMatches(para);
      final text = StringBuffer();
      var boldRuns = 0;
      var textRuns = 0;
      for (final r in runs) {
        final run = r.group(0)!;
        final sb = StringBuffer();
        for (final m in RegExp(
          r'<w:t(?: [^>]*)?>(.*?)</w:t>|<w:tab/>|<w:br/>',
          dotAll: true,
        ).allMatches(run)) {
          final g = m.group(0)!;
          sb.write(
            g == '<w:tab/>'
                ? '\t'
                : g == '<w:br/>'
                ? '\n'
                : _unescape(m.group(1) ?? ''),
          );
        }
        if (sb.isEmpty) continue;
        textRuns++;
        if (RegExp(r'<w:b(?: w:val="(?!0|false)[^"]*")?/>').hasMatch(run)) {
          boldRuns++;
        }
        text.write(sb);
      }
      final line = text.toString().trimRight();
      if (line.trim().isEmpty) continue;
      final isHeading = RegExp(
        r'<w:pStyle w:val="(?:Heading\d*|Title|Subtitle)"',
      ).hasMatch(para);
      final isList = para.contains('<w:numPr>');
      blocks.add(
        SvDocBlock(
          line,
          style: isHeading
              ? SvBlockStyle.heading
              : isList
              ? SvBlockStyle.list
              : SvBlockStyle.normal,
          isBold: textRuns > 0 && boldRuns == textRuns,
        ),
      );
      if (blocks.length >= maxParagraphs) break;
    }
    return SvDocText(isSlides: false, pages: [blocks]);
  }

  /// One page per `ppt/slides/slideN.xml`, the slide's text in document order.
  static SvDocText? parsePptx(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } on Object {
      return null;
    }
    if (zip.files.isEmpty) return null;
    final slides = <(int, String)>[];
    for (final f in zip.files) {
      final m = RegExp(r'^ppt/slides/slide(\d+)\.xml$').firstMatch(f.name);
      if (m != null && f.isFile) slides.add((int.parse(m[1]!), f.name));
    }
    if (slides.isEmpty) return null;
    slides.sort((a, b) => a.$1.compareTo(b.$1));
    final pages = <List<SvDocBlock>>[];
    for (final (_, name) in slides) {
      final xml = _entryText(zip, name) ?? '';
      final blocks = <SvDocBlock>[];
      for (final p in RegExp(
        r'<a:p>.*?</a:p>|<a:p .*?</a:p>',
        dotAll: true,
      ).allMatches(xml)) {
        final text = RegExp(r'<a:t>(.*?)</a:t>', dotAll: true)
            .allMatches(p.group(0)!)
            .map((m) => _unescape(m.group(1) ?? ''))
            .join();
        if (text.trim().isNotEmpty) blocks.add(SvDocBlock(text.trim()));
      }
      if (blocks.isNotEmpty) {
        final first = blocks.first;
        blocks[0] = SvDocBlock(first.text, style: SvBlockStyle.heading);
      }
      pages.add(blocks);
    }
    return SvDocText(isSlides: true, pages: pages);
  }

  /// The entries of a zip (name and size), never extracted. Null when
  /// [bytes] is not a zip.
  static SvZipListing? listZip(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } on Object {
      return null;
    }
    if (zip.files.isEmpty) return null;
    final entries = <SvZipEntry>[];
    var files = 0;
    var total = 0;
    for (final f in zip.files) {
      if (!f.isFile) continue;
      files++;
      total += f.size;
      if (entries.length < maxZipEntries) {
        entries.add(SvZipEntry(f.name, f.size));
      }
    }
    return SvZipListing(entries: entries, totalFiles: files, totalSize: total);
  }
}
