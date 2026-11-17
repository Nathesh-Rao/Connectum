import 'dart:convert';

/// The kinds of column the engine knows (the web's `inferType` result).
enum EngineType { text, number, date, bool, list, json, file }

/// Value rules of the Smart View engine: dates, numbers, text forms and type
/// inference. Pure Dart, no Flutter. Ported from the web's functions and
/// checked against the BE's `vectors.json`.
class SvValues {
  SvValues._();

  static final _iso = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})'
    r'(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?'
    r'(Z|[+-]\d{2}:?\d{2})?)?$',
  );
  static final _dayFirst = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$');
  static final _numText = RegExp(r'^[-+]?\s*[$€£¥₹]?\s*\d[\d,]*(\.\d+)?\s*%?$');
  static final _idLike = RegExp(
    r'phone|mobile|\btel\b|telephone|\bfax\b|contact|zip|pin ?code|\bpin\b|'
    r'postal|aadhaar|aadhar|account|iban|ifsc|swift|ssn|barcode|isbn',
    caseSensitive: false,
  );
  static final _notMeasure = RegExp(
    r'^#$|\b(year|id|no|number|code|pin|zip|phone|mobile|age|rank|sr)\b\.?',
    caseSensitive: false,
  );

  /// True when a value counts as blank (null, empty or only spaces).
  static bool isBlank(Object? v) =>
      v == null || (v is String && v.trim().isEmpty);

  /// A date as epoch milliseconds, or null. A number above 1e11 is epoch ms;
  /// ISO `yyyy-mm-dd[ T hh:mm[:ss[.f]][Z|+hh:mm]]` (date-only and zoneless
  /// are local); `d/m/yyyy` and `d-m-yyyy` are day first.
  static int? toTime(Object? v) {
    if (v is num) {
      return v.isFinite && v > 1e11 ? v.toInt() : null;
    }
    if (v is! String) return null;
    final s = v.trim();
    final m = _iso.firstMatch(s);
    if (m != null) {
      final y = int.parse(m[1]!);
      final mo = int.parse(m[2]!);
      final d = int.parse(m[3]!);
      final h = m[4] == null ? 0 : int.parse(m[4]!);
      final mi = m[5] == null ? 0 : int.parse(m[5]!);
      final sec = m[6] == null ? 0 : int.parse(m[6]!);
      final ms = m[7] == null
          ? 0
          : int.parse(m[7]!.padRight(3, '0').substring(0, 3));
      if (!_validDay(y, mo, d) || h > 23 || mi > 59 || sec > 59) return null;
      final zone = m[8];
      if (zone == null) {
        return DateTime(y, mo, d, h, mi, sec, ms).millisecondsSinceEpoch;
      }
      final utc = DateTime.utc(y, mo, d, h, mi, sec, ms).millisecondsSinceEpoch;
      if (zone == 'Z') return utc;
      final sign = zone.startsWith('-') ? -1 : 1;
      final digits = zone.substring(1).replaceAll(':', '');
      final offset =
          int.parse(digits.substring(0, 2)) * 60 +
          int.parse(digits.substring(2));
      return utc - sign * offset * 60000;
    }
    final f = _dayFirst.firstMatch(s);
    if (f != null) {
      final d = int.parse(f[1]!);
      final mo = int.parse(f[2]!);
      final y = int.parse(f[3]!);
      if (!_validDay(y, mo, d)) return null;
      return DateTime(y, mo, d).millisecondsSinceEpoch;
    }
    return null;
  }

  static bool _validDay(int y, int mo, int d) {
    if (mo < 1 || mo > 12 || d < 1) return false;
    return DateTime.utc(y, mo, d).day == d;
  }

  /// The local calendar day of [ms] as a sortable integer (yyyymmdd).
  static int dayOf(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return t.year * 10000 + t.month * 100 + t.day;
  }

  /// A number, or null. A finite number, or text like `1,200.50`, `$1,200`,
  /// `45%` (the percent sign is dropped, not divided). `.5` is not a number.
  static double? toNum(Object? v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is! String) return null;
    final s = v.trim();
    if (!_numText.hasMatch(s)) return null;
    final clean = s.replaceAll(RegExp(r'[,$€£¥₹%+\s]'), '');
    return double.tryParse(clean);
  }

  /// A number the way a column may be inferred as numeric: not a code with a
  /// leading zero and not ten or more digits.
  static bool _isAmount(Object? v) {
    if (v is num) return v.isFinite;
    if (v is! String) return false;
    final s = v.trim();
    if (toNum(s) == null) return false;
    if (RegExp(r'^0\d').hasMatch(s)) return false;
    if (RegExp(r'\d{10,}').hasMatch(s.replaceAll(',', ''))) return false;
    return true;
  }

  static bool _isBoolValue(Object? v) =>
      v is bool ||
      (v is String &&
          (v.trim().toLowerCase() == 'true' ||
              v.trim().toLowerCase() == 'false'));

  static Object? _decoded(Object? v) {
    if (v is! String) return v;
    final s = v.trim();
    if (s.length < 2) return v;
    final isList = s.startsWith('[') && s.endsWith(']');
    final isMap = s.startsWith('{') && s.endsWith('}');
    if (!isList && !isMap) return v;
    try {
      return jsonDecode(s);
    } on FormatException {
      return v;
    }
  }

  /// The text form of a value, as search and sort read it.
  static String plain(Object? v) {
    final d = _decoded(v);
    if (d == null) return '';
    if (d is String) return d;
    if (d is List) {
      if (d.isNotEmpty && d.every((e) => e is Map)) {
        return d.length == 1 ? _short(d.first) : '${d.length} items';
      }
      if (d.isEmpty) return v is String ? 'empty' : '';
      return _flat(d).join(', ');
    }
    if (d is Map) {
      return d.isEmpty && v is String ? 'empty' : _short(d);
    }
    if (d is double && d.isFinite && d == d.truncateToDouble()) {
      return '${d.toInt()}';
    }
    return '$d';
  }

  static Iterable<String> _flat(List<Object?> l) sync* {
    for (final e in l) {
      if (e is List) {
        yield* _flat(e);
      } else {
        yield e == null ? '' : '$e';
      }
    }
  }

  static String _short(Object? o) {
    if (o is! Map) return '$o';
    final parts = <String>[];
    var n = 0;
    for (final e in o.entries) {
      if (n == 4) {
        parts.add('+${o.length - 4} more');
        break;
      }
      final v = e.value;
      final shown = v is Map
          ? '${v.length} field${v.length == 1 ? '' : 's'}'
          : v is List
          ? _flat(v).join(', ')
          : '${v ?? ''}';
      parts.add('${e.key}: $shown');
      n++;
    }
    return parts.join(' · ');
  }

  /// Whether `name` is an identifier-like column name (phone, account...).
  static bool isIdLike(String name) => _idLike.hasMatch(name);

  /// The kind of a column from up to 200 filled values and its name.
  static EngineType inferType(Iterable<Object?> values, String name) {
    if (_idLike.hasMatch(name)) return EngineType.text;
    var lists = 0, objects = 0, bools = 0, numbers = 0, dates = 0, n = 0;
    var texts = 0;
    for (final raw in values) {
      if (isBlank(raw)) continue;
      if (n == 200) break;
      n++;
      final v = _decoded(raw);
      if (v is List) {
        lists++;
      } else if (v is Map) {
        objects++;
      } else if (_isBoolValue(v)) {
        bools++;
      } else if (toTime(v) != null) {
        dates++;
      } else if (_isAmount(v)) {
        numbers++;
      } else {
        texts++;
      }
    }
    if (n == 0 || texts > 0) return EngineType.text;
    if (lists > 0 && lists + objects == n) {
      return objects > 0 ? EngineType.json : EngineType.list;
    }
    if (objects > 0 && lists + objects == n) return EngineType.json;
    if (bools == n) return EngineType.bool;
    if (numbers == n) return EngineType.number;
    if (dates == n) return EngineType.date;
    return EngineType.text;
  }

  /// Whether a number column may be summed: its key and label do not hold a
  /// whole word like year, id, no, code (`Pincode` is, `Pin code` is not).
  static bool isMeasure(String key, String label, EngineType type) =>
      type == EngineType.number &&
      !_notMeasure.hasMatch(key) &&
      !_notMeasure.hasMatch(label);
}
