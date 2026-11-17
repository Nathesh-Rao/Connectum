import '../models/ids.dart';
import 'models/sv_source.dart';

/// How a saved value becomes the text of a Smart View cell (BE document
/// section 3.8.1, the web's `formatCell` / `textValue`). A blank value is the
/// dash; nothing ever shows as `null`, `undefined` or `[object Object]`.
/// Numbers use `,` and `.` and dates English month names: the app has no
/// locale package, so the device's own number and date format is not applied.
class SvCell {
  SvCell._();

  static const dash = '–';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static final _fileId = RegExp(r'^[0-9a-fA-F]{24}$');
  static final _plainNumber = RegExp(r'^-?\d+(\.\d+)?$');
  static final _dateTime = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?\s*(Z|[+-]\d{2}:?\d{2})?$',
  );

  /// The text of [value] for field [field]; [labels] and [files] are the
  /// row's own (a received record has neither).
  static String of(
    SvField? field,
    Object? value, {
    Map<String, dynamic> labels = const {},
    Map<String, dynamic> files = const {},
    String? name,
  }) {
    final key = field?.name ?? name ?? '';
    final type = field?.type ?? 'text';
    final text = switch (type) {
      'number' || 'wholenumber' => _number(value),
      'date' || 'slot' => _date(value),
      'toggle' => _toggle(value),
      'location' => _location(value),
      'payment' => _payment(value),
      'file' => _files(value, files[key]),
      'selection' ||
      'list' ||
      'status' ||
      'people' => _label(value, labels[key]),
      _ => field?.isRich ?? false ? richWords(_plain(value)) : _plain(value),
    };
    return text.trim().isEmpty ? dash : text;
  }

  /// A text with the markup taken out: breaks become a space, a script or
  /// style block goes with its content, entities are read, white space is
  /// one space. Never drawn as markup.
  static String richWords(String html) {
    var s = html;
    s = s.replaceAll(
      RegExp(r'<(script|style)\b[\s\S]*?(</\1\s*>|$)', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'<br\s*/?>|</(p|div|li|h[1-6]|tr)\s*>', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      switch (e) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
        case 'nbsp':
          return ' ';
      }
      if (e.startsWith('#x')) {
        final c = int.tryParse(e.substring(2), radix: 16);
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      if (e.startsWith('#')) {
        final c = int.tryParse(e.substring(1));
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      return m.group(0)!;
    });
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _plain(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is num) return _trim(v);
    if (v is List) {
      return v.map(_plain).where((x) => x.trim().isNotEmpty).join(', ');
    }
    if (v is Map) return _short(v);
    return idText(v);
  }

  static String _short(Map v) {
    final parts = [
      for (final e in v.entries)
        if (e.value is! Map && e.value is! List && e.value != null)
          '${e.key}: ${_plain(e.value)}'
        else if (e.value is List)
          '${e.key}: ${(e.value as List).length} items'
        else if (e.value is Map)
          '${e.key}: ${(e.value as Map).length} fields',
    ];
    return parts.join(' · ');
  }

  static String _trim(num n) {
    if (n is int || n == n.truncateToDouble()) return n.toInt().toString();
    return n.toString();
  }

  static String _number(Object? v) {
    if (v == null) return '';
    if (v is num) return _grouped(v);
    if (v is String) {
      final t = v.trim();
      if (!_plainNumber.hasMatch(t)) return v;
      final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
      final intPart = t.split('.').first.replaceAll('-', '');
      // Long digit runs and leading zeros are codes, not amounts.
      if (digits.length >= 10 || (intPart.length > 1 && intPart[0] == '0')) {
        return v;
      }
      return _grouped(num.parse(t));
    }
    return _plain(v);
  }

  static String _grouped(num n) {
    final fixed = n.toStringAsFixed(2);
    var whole = fixed.split('.').first;
    var frac = fixed.split('.').last.replaceFirst(RegExp(r'0+$'), '');
    final isNeg = whole.startsWith('-');
    if (isNeg) whole = whole.substring(1);
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    final out = frac.isEmpty ? buf.toString() : '$buf.$frac';
    return isNeg && out != '0' ? '-$out' : out;
  }

  static String _date(Object? v) {
    if (v == null) return '';
    if (v is num) return _stamp(DateTime.fromMillisecondsSinceEpoch(v.toInt()));
    final t = idText(v).trim();
    final m = _dateTime.firstMatch(t);
    if (m == null) return t;
    final hasTime = m.group(4) != null;
    final zone = m.group(7);
    var d = DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      hasTime ? int.parse(m.group(4)!) : 0,
      hasTime ? int.parse(m.group(5)!) : 0,
    );
    if (zone != null && hasTime) {
      final parsed = DateTime.tryParse(t.replaceFirst(' ', 'T'));
      if (parsed != null) d = parsed.toLocal();
    }
    return hasTime ? _stamp(d) : _day(d);
  }

  static String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

  static String _stamp(DateTime d) =>
      '${_day(d)}, ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  /// A record's own time (`ts`, epoch ms) in the device's zone.
  static String stamp(int ts) =>
      ts <= 0 ? dash : _stamp(DateTime.fromMillisecondsSinceEpoch(ts));

  static String _toggle(Object? v) {
    if (v == null) return '';
    final t = idText(v).trim().toLowerCase();
    if (t.isEmpty) return '';
    if (t == 'yes' || t == 'true' || t == '1') return 'Yes';
    if (t == 'no' || t == 'false' || t == '0') return 'No';
    return idText(v);
  }

  static String _label(Object? value, Object? label) {
    final l = _plain(label);
    if (l.trim().isNotEmpty) return l;
    return _plain(value);
  }

  static String _location(Object? v) {
    if (v is Map) {
      final address = idText(v['address']).trim();
      if (address.isNotEmpty) return address;
      final lat = idText(v['lat']);
      final lng = idText(v['lng']);
      return lat.isNotEmpty && lng.isNotEmpty ? '$lat, $lng' : '';
    }
    return _plain(v);
  }

  static String _payment(Object? v) {
    if (v is! Map) return _plain(v);
    final amountRaw = v['amount'];
    final amount = amountRaw == null ? null : num.tryParse('$amountRaw');
    final method = idText(v['method']).trim();
    if (amount == null && method.isEmpty) return '';
    final currency = idText(v['currency']).trim();
    final status = idText(v['status']).toLowerCase();
    final parts = [
      [
        if (currency.isNotEmpty) currency,
        if (amount != null) _trim(amount),
      ].join(' '),
      if (method.isNotEmpty) method,
      if (status == 'paid') 'Paid' else if (status == 'pending') 'Pay later',
    ].where((p) => p.isNotEmpty);
    return parts.join(' · ');
  }

  static String _files(Object? value, Object? info) {
    final ids = [
      if (value is List)
        for (final x in value)
          if (_fileId.hasMatch(idText(x))) idText(x),
    ];
    if (ids.isEmpty) return '';
    final byId = <String, String>{
      if (info is List)
        for (final f in info)
          if (f is Map) idText(f['id']): idText(f['name']),
    };
    final names = [
      for (final id in ids) (byId[id] ?? '').isEmpty ? 'File' : byId[id]!,
    ];
    return names.join(', ');
  }
}
