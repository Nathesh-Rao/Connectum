import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// How a log line is drawn.
enum LogLineKind { normal, muted, warning, error }

/// Where a search match sits: the line and the offset inside it.
class LogHit {
  const LogHit(this.line, this.start);

  final int line;
  final int start;
}

class LogSearchResult {
  const LogSearchResult(this.hits, {this.isCut = false});

  static const empty = LogSearchResult([]);

  final List<LogHit> hits;

  /// True when more matches exist than were kept.
  final bool isCut;
}

/// The lines of a log file with how each is drawn. Pure Dart, so it can be
/// built off the UI thread.
class LogDocument {
  const LogDocument(this.lines, this.kinds, this.longest);

  static const maxHits = 5000;

  static final empty = LogDocument(const [], Uint8List(0), 0);

  static final _entry = RegExp(r'^\d{2}:\d{2}:\d{2}(?:\.\d+)?\s+([EWI])\s');

  final List<String> lines;
  final Uint8List kinds;

  /// Length in characters of the longest line.
  final int longest;

  bool get isEmpty => lines.isEmpty;

  LogLineKind kindOf(int i) => LogLineKind.values[kinds[i]];

  /// Reads and classifies the file at [path]. Runs in an isolate.
  static Future<LogDocument> readFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return parse(utf8.decode(bytes, allowMalformed: true));
  }

  static LogDocument parse(String text) {
    final lines = const LineSplitter().convert(text);
    final kinds = Uint8List(lines.length);
    var isHeader = true;
    var level = LogLineKind.normal;
    var longest = 0;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.length > longest) longest = l.length;
      final m = _entry.firstMatch(l);
      LogLineKind kind;
      if (m != null) {
        isHeader = false;
        level = switch (m.group(1)) {
          'E' => LogLineKind.error,
          'W' => LogLineKind.warning,
          _ => LogLineKind.normal,
        };
        kind = level;
      } else if (l.startsWith('====') ||
          l.startsWith('-- ') ||
          l.startsWith('SESSION START')) {
        if (l.startsWith('-- ')) isHeader = false;
        level = LogLineKind.normal;
        kind = LogLineKind.muted;
      } else if (isHeader) {
        kind = LogLineKind.muted;
      } else if (l.startsWith(' ')) {
        kind = level;
      } else {
        level = LogLineKind.normal;
        kind = LogLineKind.normal;
      }
      kinds[i] = kind.index;
    }
    return LogDocument(lines, kinds, longest);
  }

  /// Case-insensitive matches of [query], at most [maxHits].
  static LogSearchResult find(List<String> lines, String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return LogSearchResult.empty;
    final hits = <LogHit>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].toLowerCase();
      var from = 0;
      while (true) {
        final at = l.indexOf(q, from);
        if (at < 0) break;
        if (hits.length >= maxHits) return LogSearchResult(hits, isCut: true);
        hits.add(LogHit(i, at));
        from = at + q.length;
      }
    }
    return LogSearchResult(hits);
  }
}

/// Rows of the viewer: each line, cut every [charsPerRow] characters when
/// lines wrap (0 = no wrap, one row per line). Every row has the same height,
/// so jumps and search are exact however long the file is.
class LogRowIndex {
  LogRowIndex(this.doc, this.charsPerRow)
    : _first = Int32List(doc.lines.length + 1) {
    var rows = 0;
    for (var i = 0; i < doc.lines.length; i++) {
      _first[i] = rows;
      rows += _rowsOf(doc.lines[i].length);
    }
    _first[doc.lines.length] = rows;
  }

  final LogDocument doc;
  final int charsPerRow;
  final Int32List _first;

  int _rowsOf(int length) => charsPerRow <= 0 || length <= charsPerRow
      ? 1
      : (length + charsPerRow - 1) ~/ charsPerRow;

  int get rowCount => _first[doc.lines.length];

  /// The line a row belongs to.
  int lineOf(int row) {
    var lo = 0;
    var hi = doc.lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_first[mid] <= row) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The characters of [line] shown in [row]: start (inclusive), end.
  (int, int) rangeOf(int row, int line) {
    final length = doc.lines[line].length;
    if (charsPerRow <= 0) return (0, length);
    final start = (row - _first[line]) * charsPerRow;
    return (start, math.min(length, start + charsPerRow));
  }

  /// The row that shows offset [start] of [line].
  int rowOf(int line, int start) =>
      _first[line] + (charsPerRow <= 0 ? 0 : start ~/ charsPerRow);
}

/// Reads and searches off the UI thread. Tests subclass it.
class LogTextReader {
  const LogTextReader();

  Future<LogDocument> read(File file) =>
      compute(LogDocument.readFile, file.path);

  Future<LogSearchResult> search(LogDocument doc, String query) =>
      compute(_search, (doc.lines, query));

  static LogSearchResult _search((List<String>, String) args) =>
      LogDocument.find(args.$1, args.$2);
}
