import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml_events.dart';

import 'sv_preview_parsers.dart';

/// Reads the cached values of an .xlsx for the read-only preview. Formulas are
/// never evaluated, macros never run and links never followed: only the
/// stored value of each cell is read, as text. Pure and safe to run in an
/// isolate. Anything unusual (too big, too many entries, corrupt) gives null.
class SvXlsxParser {
  SvXlsxParser._();

  static const maxFileBytes = 5 * 1024 * 1024;
  static const maxUnzippedBytes = 20 * 1024 * 1024;
  static const maxEntries = 2000;
  static const maxSheets = 30;
  static const maxRows = 200;
  static const maxColumns = 30;
  static const maxScannedCells = 300000;
  static const maxStrings = 200000;
  static const maxCellChars = 1000;

  /// The book, or null when it is not a usable .xlsx or over a limit.
  static SvSheetBook? parse(Uint8List bytes) {
    try {
      return _Reader(bytes).read();
    } on Object {
      return null;
    }
  }
}

class _Unsafe implements Exception {
  const _Unsafe();
}

enum _Kind { general, number, percent, date, time, dateTime }

class _Fmt {
  const _Fmt(this.kind, {this.decimals = 0, this.isThousands = false});

  final _Kind kind;
  final int decimals;
  final bool isThousands;

  static const general = _Fmt(_Kind.general);
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  final _entries = <String, ArchiveFile>{};
  var _unzipped = 0;
  var _scanned = 0;
  var _is1904 = false;
  var _strings = <String>[];
  var _styles = <_Fmt>[];

  SvSheetBook? read() {
    if (bytes.length > SvXlsxParser.maxFileBytes) return null;
    final zip = ZipDecoder().decodeBytes(bytes);
    if (zip.files.length > SvXlsxParser.maxEntries) return null;
    var declared = 0;
    for (final f in zip.files) {
      if (!f.isFile) continue;
      declared += f.size;
      if (declared > SvXlsxParser.maxUnzippedBytes) return null;
      _entries[_clean(f.name)] = f;
    }
    final workbook = _text('xl/workbook.xml');
    if (workbook == null) return null;
    final sheets = _sheets(workbook, _text('xl/_rels/workbook.xml.rels') ?? '');
    if (sheets.isEmpty) return null;
    _strings = _sharedStrings(_text('xl/sharedStrings.xml'));
    _styles = _styleFormats(_text('xl/styles.xml'));
    final tables = <SvSheetTable>[];
    for (final (name, path) in sheets) {
      final xml = _text(path);
      if (xml == null) continue;
      tables.add(_sheet(name, xml));
    }
    return tables.isEmpty ? null : SvSheetBook(tables);
  }

  static String _clean(String name) =>
      name.startsWith('/') ? name.substring(1) : name;

  /// The text of one entry; the real size counts against the limit, not the
  /// one the header declares.
  String? _text(String name) {
    final f = _entries[name];
    if (f == null) return null;
    final data = f.content;
    _unzipped += data.length;
    if (_unzipped > SvXlsxParser.maxUnzippedBytes) throw const _Unsafe();
    return utf8.decode(data, allowMalformed: true);
  }

  List<(String, String)> _sheets(String workbook, String rels) {
    final targets = <String, String>{};
    for (final e in parseEvents(rels)) {
      if (e is! XmlStartElementEvent || e.localName != 'Relationship') continue;
      final a = _attrs(e);
      if (a['TargetMode']?.toLowerCase() == 'external') continue;
      final id = a['Id'];
      final target = a['Target'];
      if (id != null && target != null) targets[id] = _resolve(target);
    }
    final out = <(String, String)>[];
    for (final e in parseEvents(workbook)) {
      if (e is! XmlStartElementEvent) continue;
      if (e.localName == 'workbookPr') {
        final v = _attrs(e)['date1904'];
        _is1904 = v == '1' || v == 'true';
      } else if (e.localName == 'sheet') {
        final a = _attrs(e);
        final state = a['state'];
        if (state == 'hidden' || state == 'veryHidden') continue;
        final path = targets[a['id']];
        if (path == null) continue;
        final name = a['name'] ?? 'Sheet ${out.length + 1}';
        out.add((name, path));
        if (out.length > SvXlsxParser.maxSheets) throw const _Unsafe();
      }
    }
    return out;
  }

  /// Local attribute names (`r:id` is `id`).
  static Map<String, String> _attrs(XmlStartElementEvent e) => {
    for (final a in e.attributes) a.localName: a.value,
  };

  static String _resolve(String target) {
    final parts = <String>[];
    final full = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    for (final p in full.split('/')) {
      if (p == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (p.isNotEmpty && p != '.') {
        parts.add(p);
      }
    }
    return parts.join('/');
  }

  List<String> _sharedStrings(String? xml) {
    final out = <String>[];
    if (xml == null) return out;
    final buf = StringBuffer();
    var inT = false;
    var inPhonetic = false;
    for (final e in parseEvents(xml)) {
      if (e is XmlStartElementEvent) {
        switch (e.localName) {
          case 'si':
            buf.clear();
          case 'rPh':
            inPhonetic = true;
          case 't':
            inT = !e.isSelfClosing;
        }
      } else if (e is XmlEndElementEvent) {
        switch (e.localName) {
          case 'si':
            out.add(_cut(buf.toString()));
            if (out.length > SvXlsxParser.maxStrings) throw const _Unsafe();
          case 'rPh':
            inPhonetic = false;
          case 't':
            inT = false;
        }
      } else if (inT && !inPhonetic) {
        if (e is XmlTextEvent) buf.write(e.value);
        if (e is XmlCDATAEvent) buf.write(e.value);
      }
    }
    return out;
  }

  List<_Fmt> _styleFormats(String? xml) {
    if (xml == null) return const [];
    final custom = <int, String>{};
    final out = <_Fmt>[];
    var inXfs = false;
    for (final e in parseEvents(xml)) {
      if (e is XmlStartElementEvent) {
        if (e.localName == 'numFmt') {
          final a = _attrs(e);
          final id = int.tryParse(a['numFmtId'] ?? '');
          if (id != null) custom[id] = a['formatCode'] ?? '';
        } else if (e.localName == 'cellXfs') {
          inXfs = true;
        } else if (e.localName == 'xf' && inXfs) {
          final id = int.tryParse(_attrs(e)['numFmtId'] ?? '') ?? 0;
          out.add(_formatOf(id, custom[id]));
        }
      } else if (e is XmlEndElementEvent && e.localName == 'cellXfs') {
        inXfs = false;
      }
    }
    return out;
  }

  static _Fmt _formatOf(int id, String? code) {
    switch (id) {
      case 1:
        return const _Fmt(_Kind.number);
      case 2:
        return const _Fmt(_Kind.number, decimals: 2);
      case 3:
      case 37:
      case 38:
        return const _Fmt(_Kind.number, isThousands: true);
      case 4:
      case 39:
      case 40:
        return const _Fmt(_Kind.number, decimals: 2, isThousands: true);
      case 9:
        return const _Fmt(_Kind.percent);
      case 10:
        return const _Fmt(_Kind.percent, decimals: 2);
      case 14:
      case 15:
      case 16:
      case 17:
        return const _Fmt(_Kind.date);
      case 18:
      case 19:
      case 20:
      case 21:
      case 45:
      case 46:
      case 47:
        return const _Fmt(_Kind.time);
      case 22:
        return const _Fmt(_Kind.dateTime);
    }
    return code == null ? _Fmt.general : _customFormat(code);
  }

  static _Fmt _customFormat(String code) {
    var section = code.split(';').first;
    section = section
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\\.'), '')
        .toLowerCase();
    if (section.isEmpty || section == 'general' || section == '@') {
      return _Fmt.general;
    }
    final hasDay = section.contains(RegExp('[yd]'));
    final hasClock = section.contains(RegExp('[hs]'));
    final hasMonth = section.contains('m');
    if (hasDay || hasClock || (hasMonth && !section.contains(RegExp('[0#]')))) {
      if (hasClock && (hasDay || section.contains('mmm'))) {
        return const _Fmt(_Kind.dateTime);
      }
      return hasClock ? const _Fmt(_Kind.time) : const _Fmt(_Kind.date);
    }
    if (!section.contains(RegExp('[0#?]'))) return _Fmt.general;
    final dot = section.indexOf('.');
    var decimals = 0;
    if (dot >= 0) {
      for (var i = dot + 1; i < section.length; i++) {
        if ('0#?'.contains(section[i])) {
          decimals++;
        } else {
          break;
        }
      }
    }
    if (section.contains('e+') || section.contains('e-')) return _Fmt.general;
    return _Fmt(
      section.contains('%') ? _Kind.percent : _Kind.number,
      decimals: decimals,
      isThousands: RegExp('[0#],[0#]').hasMatch(section),
    );
  }

  SvSheetTable _sheet(String name, String xml) {
    final rows = <List<String>>[];
    var isCut = false;
    var rowNo = 0;
    List<String>? row;
    var col = 0;
    String? type;
    int? style;
    var value = StringBuffer();
    var inV = false;
    var inIs = false;
    var inT = false;
    var inPhonetic = false;
    var hasValue = false;

    for (final e in parseEvents(xml)) {
      if (e is XmlStartElementEvent) {
        switch (e.localName) {
          case 'row':
            final r = int.tryParse(_attrs(e)['r'] ?? '') ?? rowNo + 1;
            rowNo = r;
            if (r > SvXlsxParser.maxRows) {
              isCut = true;
              return _table(name, rows, isCut);
            }
            while (rows.length < r - 1) {
              rows.add(const <String>[]);
            }
            row = <String>[];
            rows.add(row);
            col = -1;
          case 'c':
            final a = _attrs(e);
            final at = _column(a['r']);
            col = at ?? col + 1;
            type = a['t'];
            style = int.tryParse(a['s'] ?? '');
            value = StringBuffer();
            hasValue = false;
            if (++_scanned > SvXlsxParser.maxScannedCells) {
              throw const _Unsafe();
            }
            if (e.isSelfClosing) {
              type = null;
            }
          case 'v':
            inV = !e.isSelfClosing;
            hasValue = true;
          case 'is':
            inIs = true;
            hasValue = true;
          case 'rPh':
            inPhonetic = true;
          case 't':
            inT = inIs && !e.isSelfClosing;
        }
      } else if (e is XmlEndElementEvent) {
        switch (e.localName) {
          case 'v':
            inV = false;
          case 'is':
            inIs = false;
          case 'rPh':
            inPhonetic = false;
          case 't':
            inT = false;
          case 'c':
            final r = row;
            if (r == null || !hasValue) break;
            if (col >= SvXlsxParser.maxColumns) {
              isCut = true;
              break;
            }
            while (r.length < col) {
              r.add('');
            }
            final text = _display(type, value.toString(), style);
            if (r.length == col) {
              r.add(text);
            } else {
              r[col] = text;
            }
            hasValue = false;
        }
      } else if ((inV || (inT && !inPhonetic)) &&
          (e is XmlTextEvent || e is XmlCDATAEvent)) {
        value.write(e is XmlTextEvent ? e.value : (e as XmlCDATAEvent).value);
      }
    }
    return _table(name, rows, isCut);
  }

  static SvSheetTable _table(String name, List<List<String>> rows, bool isCut) {
    var last = rows.length;
    while (last > 0 && rows[last - 1].every((c) => c.isEmpty)) {
      last--;
    }
    final kept = rows.sublist(0, last);
    return SvSheetTable(
      name: _cut(name, 31),
      rows: kept,
      isCut: isCut,
      totalRows: kept.length,
    );
  }

  /// "C12" is column index 2.
  static int? _column(String? ref) {
    if (ref == null) return null;
    var n = 0;
    var seen = false;
    for (final u in ref.codeUnits) {
      final up = u & ~0x20;
      if (up < 0x41 || up > 0x5a) break;
      n = n * 26 + (up - 0x40);
      seen = true;
      if (n > 20000) return null;
    }
    return seen ? n - 1 : null;
  }

  String _display(String? type, String raw, int? style) {
    switch (type) {
      case 's':
        final i = int.tryParse(raw.trim());
        return i != null && i >= 0 && i < _strings.length ? _strings[i] : '';
      case 'b':
        return raw.trim() == '1' ? 'TRUE' : 'FALSE';
      case 'str':
      case 'inlineStr':
      case 'e':
      case 'd':
        return _cut(raw);
    }
    final v = double.tryParse(raw.trim());
    if (v == null || v.isNaN || v.isInfinite) return _cut(raw);
    final fmt = style != null && style >= 0 && style < _styles.length
        ? _styles[style]
        : _Fmt.general;
    return _number(v, fmt);
  }

  String _number(double v, _Fmt f) {
    switch (f.kind) {
      case _Kind.date:
      case _Kind.time:
      case _Kind.dateTime:
        return _dateText(v, f.kind) ?? _general(v);
      case _Kind.percent:
        return '${_fixed(v * 100, f.decimals, false)}%';
      case _Kind.number:
        return _fixed(v, f.decimals, f.isThousands);
      case _Kind.general:
        return _general(v);
    }
  }

  String? _dateText(double v, _Kind kind) {
    if (v < 0 || v >= 2958466) return null;
    final days = v.floor();
    final seconds = ((v - days) * 86400).round();
    final base = _is1904 ? DateTime.utc(1904) : DateTime.utc(1899, 12, 30);
    var d = base.add(Duration(days: days, seconds: seconds));
    if (!_is1904 && days < 60) d = d.add(const Duration(days: 1));
    String two(int n) => n.toString().padLeft(2, '0');
    final date =
        '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-'
        '${two(d.day)}';
    final time = '${two(d.hour)}:${two(d.minute)}';
    return switch (kind) {
      _Kind.date => date,
      _Kind.time => time,
      _ => '$date $time',
    };
  }

  static String _fixed(double v, int decimals, bool isThousands) {
    final s = v.toStringAsFixed(decimals.clamp(0, 10));
    if (!isThousands) return s;
    final neg = s.startsWith('-');
    final body = neg ? s.substring(1) : s;
    final dot = body.indexOf('.');
    final whole = dot < 0 ? body : body.substring(0, dot);
    final rest = dot < 0 ? '' : body.substring(dot);
    final out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
      out.write(whole[i]);
    }
    return '${neg ? '-' : ''}$out$rest';
  }

  static String _general(double v) {
    if (v == v.truncateToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    var s = v.toStringAsPrecision(10);
    final e = s.indexOf('e');
    final mantissa = e < 0 ? s : s.substring(0, e);
    final tail = e < 0 ? '' : s.substring(e);
    s = mantissa.contains('.')
        ? mantissa
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : mantissa;
    return '$s$tail';
  }

  static String _cut(String s, [int max = SvXlsxParser.maxCellChars]) =>
      s.length <= max ? s : s.substring(0, max);
}
