import 'dart:convert';

import '../../core/utils/chat_time.dart';
import 'ids.dart';

enum FormEntryKind { text, yes, no, location }

/// One field of a submission, ready to show: its caption and a readable value.
/// Parsing is defensive: a value of a type nobody planned for becomes readable
/// text, never an error, and an empty value gives no entry at all.
class FormEntry {
  const FormEntry({
    required this.name,
    required this.caption,
    required this.text,
    this.kind = FormEntryKind.text,
    this.coordinates,
  });

  static const pinnedLocation = 'Pinned location';

  final String name;
  final String caption;
  final String text;
  final FormEntryKind kind;

  /// "12.918562, 77.57447" for a location that carries coordinates.
  final String? coordinates;

  bool get isLocation => kind == FormEntryKind.location;

  static final _iso = RegExp(
    r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$',
  );

  /// Null when the value is empty (those are hidden). [type] is the form
  /// definition's field type when it is known.
  static FormEntry? parse(
    String name,
    String caption,
    Object? raw, {
    String type = '',
  }) {
    final value = _decode(raw);
    if (_isEmpty(value)) return null;
    final place = _place(value);
    if (place != null) {
      return FormEntry(
        name: name,
        caption: caption,
        text: place.address.isEmpty ? pinnedLocation : place.address,
        kind: FormEntryKind.location,
        coordinates: place.coordinates,
      );
    }
    if (type == 'location' && value is String) {
      return FormEntry(
        name: name,
        caption: caption,
        text: value.trim(),
        kind: FormEntryKind.location,
      );
    }
    final yesNo = _yesNo(value);
    if (yesNo != null) {
      return FormEntry(
        name: name,
        caption: caption,
        text: yesNo ? 'Yes' : 'No',
        kind: yesNo ? FormEntryKind.yes : FormEntryKind.no,
      );
    }
    final text = display(value);
    if (text.isEmpty) return null;
    return FormEntry(name: name, caption: caption, text: text);
  }

  /// A value as text for a table cell or a joined list: empty gives "".
  static String display(Object? raw) {
    final value = _decode(raw);
    if (_isEmpty(value)) return '';
    final place = _place(value);
    if (place != null) {
      return place.address.isEmpty ? pinnedLocation : place.address;
    }
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is num) return _number(value);
    if (value is String) return _string(value);
    if (value is List) {
      if (value.isNotEmpty && value.every((e) => e is Map)) {
        final rows = <String>[];
        for (final row in value) {
          final cells = (row as Map).values
              .map(display)
              .where((c) => c.isNotEmpty);
          if (cells.isNotEmpty)
            rows.add('${rows.length + 1}. ${cells.join(', ')}');
        }
        return rows.join('\n');
      }
      return value.map(display).where((c) => c.isNotEmpty).join(', ');
    }
    if (value is Map) {
      return [
        for (final e in value.entries)
          if (display(e.value).isNotEmpty)
            '${_humanize(idText(e.key))}: ${display(e.value)}',
      ].join(', ');
    }
    return idText(value).trim();
  }

  /// "numericText" -> "Numeric text", "section_one" -> "Section one".
  static String humanize(String name) => _humanize(name);

  static String _humanize(String name) {
    final spaced = name
        .replaceAll('_', ' ')
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]!.toLowerCase()}',
        )
        .trim();
    if (spaced.isEmpty) return name;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// Text that holds JSON (this server sends a location that way) is read as
  /// the value it holds.
  static Object? _decode(Object? raw) {
    if (raw is! String) return raw;
    final t = raw.trim();
    final isJson =
        (t.startsWith('{') && t.endsWith('}')) ||
        (t.startsWith('[') && t.endsWith(']'));
    if (!isJson) return raw;
    try {
      return jsonDecode(t);
    } on FormatException {
      return raw;
    }
  }

  static bool _isEmpty(Object? v) =>
      v == null ||
      (v is String && v.trim().isEmpty) ||
      (v is List && v.isEmpty) ||
      (v is Map && v.isEmpty);

  static bool? _yesNo(Object? v) {
    if (v is bool) return v;
    if (v is! String) return null;
    return switch (v.trim().toLowerCase()) {
      'yes' || 'true' => true,
      'no' || 'false' => false,
      _ => null,
    };
  }

  static ({String address, String? coordinates})? _place(Object? v) {
    if (v is! Map) return null;
    final lat = _coordinate(v['lat']);
    final lng = _coordinate(v['lng'] ?? v['lon'] ?? v['long']);
    if (lat == null || lng == null) return null;
    return (
      address: idText(v['address']).trim(),
      coordinates: '${_trim(lat)}, ${_trim(lng)}',
    );
  }

  static double? _coordinate(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(idText(v));

  static String _trim(double v) {
    final s = v.toStringAsFixed(6);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  static String _string(String s) {
    final t = s.trim();
    if (!_iso.hasMatch(t)) return t;
    final parsed = DateTime.tryParse(t);
    if (parsed == null) return t;
    final local = parsed.toLocal();
    final ms = local.millisecondsSinceEpoch;
    return t.length == 10
        ? ChatTime.date(ms)
        : '${ChatTime.date(ms)}, ${ChatTime.time(ms)}';
  }

  static String _number(num n) {
    if (n is double) {
      if (n.isNaN || n.isInfinite) return '';
      if (n == n.truncateToDouble() && n.abs() < 1e15) return _group(n.toInt());
      final s = n.toStringAsFixed(2);
      return s
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return _group(n.toInt());
  }

  /// Indian grouping (12,34,567) from five digits up, so a year stays "2026".
  static String _group(int n) {
    final digits = n.abs().toString();
    if (digits.length < 5) return n.toString();
    final last = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${n < 0 ? '-' : ''}${parts.join(',')},$last';
  }
}

/// A grid section of a submission: a small table.
class FormGrid {
  const FormGrid({
    required this.name,
    required this.caption,
    required this.columns,
    required this.rows,
  });

  final String name;
  final String caption;
  final List<String> columns;
  final List<List<String>> rows;

  /// The grid as one value for a card: "1. 12, test" per row.
  FormEntry? get asEntry {
    final lines = <String>[];
    for (final row in rows) {
      final cells = row.where((c) => c.isNotEmpty);
      if (cells.isNotEmpty)
        lines.add('${lines.length + 1}. ${cells.join(', ')}');
    }
    if (lines.isEmpty) return null;
    return FormEntry(name: name, caption: caption, text: lines.join('\n'));
  }
}
