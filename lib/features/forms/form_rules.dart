import '../../data/models/form_definition.dart';
import '../../data/models/ids.dart';

/// The pure rules of a form: conditions, starting values, the checks made
/// before sending and the `values` object that is sent. Values are held the
/// way the editor holds them: numbers, dates and times as text, a multi-choice
/// list as a list of strings, a location as a map or "lat, lng" text.
class FormRules {
  FormRules._();

  /// Types the form screen can fill.
  static const supportedTypes = {
    'text',
    'email',
    'url',
    'mobile',
    'wholenumber',
    'number',
    'date',
    'time',
    'list',
    'location',
    'autogenerate',
  };

  static bool isSupported(FormFieldDef f) => supportedTypes.contains(f.type);

  /// Never sent: the server makes it.
  static bool isSent(FormFieldDef f) => f.type != 'autogenerate';

  // ---- conditions -------------------------------------------------------------

  static bool isFilled(Object? v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  /// [valueOf] answers with the current value of a field by name (a row's
  /// cell first, then the form's).
  static bool matches(Object? condition, Object? Function(String) valueOf) {
    if (condition is! Map) return true;
    final all = condition['all'];
    if (all is List) return all.every((c) => matches(c, valueOf));
    final any = condition['any'];
    if (any is List) return any.isEmpty || any.any((c) => matches(c, valueOf));
    final field = idText(condition['field']);
    if (field.isEmpty) return true;
    final actual = valueOf(field);
    final expected = condition['value'];
    switch (idText(condition['op'])) {
      case 'eq':
        return _equals(actual, expected);
      case 'ne':
        return !_equals(actual, expected);
      case 'gt':
        return _compare(actual, expected, (c) => c > 0);
      case 'lt':
        return _compare(actual, expected, (c) => c < 0);
      case 'gte':
        return _compare(actual, expected, (c) => c >= 0);
      case 'lte':
        return _compare(actual, expected, (c) => c <= 0);
      case 'in':
        return expected is List && expected.any((e) => _equals(actual, e));
      case 'between':
        return expected is List &&
            expected.length == 2 &&
            _compare(actual, expected[0], (c) => c >= 0) &&
            _compare(actual, expected[1], (c) => c <= 0);
      case 'notempty':
        return isFilled(actual);
      default:
        return true;
    }
  }

  static bool _equals(Object? actual, Object? expected) {
    if (actual is List) return actual.any((a) => _equals(a, expected));
    final a = idText(actual).trim();
    final e = idText(expected).trim();
    final x = num.tryParse(a);
    final y = num.tryParse(e);
    if (x != null && y != null) return x == y;
    return a.toLowerCase() == e.toLowerCase();
  }

  static bool _compare(
    Object? actual,
    Object? expected,
    bool Function(int) test,
  ) {
    if (!isFilled(actual) || actual is List || actual is Map) return false;
    final a = idText(actual).trim();
    final e = idText(expected).trim();
    final x = num.tryParse(a);
    final y = num.tryParse(e);
    return test(x != null && y != null ? x.compareTo(y) : a.compareTo(e));
  }

  // ---- starting values ----------------------------------------------------------

  /// The value a new record starts with: the fixed default, else today for a
  /// date and now for a time (unless the field turns that off), clamped into
  /// its range. Null when there is none.
  static Object? startingValue(FormFieldDef f, DateTime now) {
    final fixed = f.defaultValue;
    switch (f.type) {
      case 'text' || 'email' || 'url' || 'mobile' || 'wholenumber' || 'number':
        return fixed == null ? null : idText(fixed);
      case 'list':
        return !f.isMulti && fixed != null ? idText(fixed) : null;
      case 'date':
        var v = fixed != null
            ? idText(fixed)
            : f.raw['defaultNow'] == false
            ? null
            : _date(now);
        if (v == null) return null;
        if (f.minText.isNotEmpty && v.compareTo(f.minText) < 0) v = f.minText;
        if (f.maxText.isNotEmpty && v.compareTo(f.maxText) > 0) v = f.maxText;
        return v;
      case 'time':
        var v = fixed != null
            ? idText(fixed)
            : f.raw['defaultNow'] == false
            ? null
            : _time(now);
        if (v == null) return null;
        if (f.minText.isNotEmpty && v.compareTo(f.minText) < 0) v = f.minText;
        if (f.maxText.isNotEmpty && v.compareTo(f.maxText) > 0) v = f.maxText;
        return v;
    }
    return null;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
  static String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// A saved value as the editor holds it.
  static Object? fromSaved(FormFieldDef f, Object? saved) {
    if (saved == null) return null;
    switch (f.type) {
      case 'list':
        if (f.isMulti) {
          return saved is List
              ? [for (final e in saved) idText(e)]
              : idText(saved).isEmpty
              ? <String>[]
              : [idText(saved)];
        }
        return idText(saved);
      case 'location':
        return saved is Map ? saved.cast<String, dynamic>() : idText(saved);
      case 'wholenumber' || 'number':
        if (saved is num && saved == saved.truncate()) {
          return saved.truncate().toString();
        }
        return idText(saved);
      default:
        return saved is Map || saved is List ? null : idText(saved);
    }
  }

  // ---- checking ----------------------------------------------------------------

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _url = RegExp(r'^https?://\S+$', caseSensitive: false);

  /// The first problem with one value, in plain words, or null.
  static String? check(FormFieldDef f, Object? value) {
    if (!isFilled(value)) {
      return f.isRequired && isSent(f) ? 'This field is required.' : null;
    }
    final text = value is String ? value.trim() : '';
    switch (f.type) {
      case 'text':
        return text.length > 5000 ? 'Use at most 5000 characters.' : null;
      case 'email':
        return _email.hasMatch(text) ? null : 'Enter a valid email address.';
      case 'url':
        return _url.hasMatch(text)
            ? null
            : 'Enter a web address starting with http:// or https://.';
      case 'mobile':
        final digits = text.replaceAll(RegExp(r'\D'), '');
        return digits.length < 6 || digits.length > 15
            ? 'Enter a valid phone number.'
            : null;
      case 'wholenumber':
        final n = int.tryParse(text);
        if (n == null) return 'Enter a whole number.';
        return _range(f, n);
      case 'number':
        final n = num.tryParse(text);
        if (n == null) return 'Enter a number.';
        return _range(f, n);
      case 'date':
        final day = DateTime.tryParse(text);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
            day == null ||
            _date(day) != text) {
          return 'Pick a date.';
        }
        if (f.minText.isNotEmpty && text.compareTo(f.minText) < 0) {
          return 'Must be on or after ${f.minText}.';
        }
        if (f.maxText.isNotEmpty && text.compareTo(f.maxText) > 0) {
          return 'Must be on or before ${f.maxText}.';
        }
        return null;
      case 'time':
        return RegExp(r'^\d{2}:\d{2}(:\d{2})?$').hasMatch(text)
            ? null
            : 'Pick a time.';
      case 'location':
        return locationOf(value) == null
            ? 'Enter latitude and longitude, like 12.97, 77.59.'
            : null;
    }
    return null;
  }

  static String? _range(FormFieldDef f, num n) {
    if (f.min != null && n < f.min!) return 'Must be at least ${f.min}.';
    if (f.max != null && n > f.max!) return 'Must be at most ${f.max}.';
    return null;
  }

  /// `{lat, lng, address?}` from a map or "lat, lng" text; null when it isn't
  /// a place.
  static Map<String, dynamic>? locationOf(Object? v) {
    if (v is Map) {
      final lat = num.tryParse(idText(v['lat']));
      final lng = num.tryParse(idText(v['lng']));
      if (lat == null || lng == null) return null;
      return {
        'lat': lat,
        'lng': lng,
        if (idText(v['address']).isNotEmpty) 'address': idText(v['address']),
      };
    }
    final parts = idText(v).split(',');
    if (parts.length != 2) return null;
    final lat = num.tryParse(parts[0].trim());
    final lng = num.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return {'lat': lat, 'lng': lng};
  }

  /// One value as it goes into `values`; null when it should be left out.
  static Object? toSent(FormFieldDef f, Object? value) {
    if (!isSent(f) || !isFilled(value)) return null;
    switch (f.type) {
      case 'wholenumber':
        return int.tryParse(idText(value).trim());
      case 'number':
        return num.tryParse(idText(value).trim());
      case 'location':
        return locationOf(value);
      case 'list':
        return value is List
            ? [for (final e in value) idText(e)]
            : idText(value);
      default:
        return idText(value).trim();
    }
  }

  // ---- server answers --------------------------------------------------------------

  /// The `details.fields` of an `invalid_values` answer, as plain words per
  /// key (`amount`, `items`, `items.1.item`).
  static Map<String, String> serverErrors(Object? details) {
    final fields = details is Map ? details['fields'] : null;
    if (fields is! Map) return const {};
    return {
      for (final e in fields.entries)
        idText(e.key): idText(e.value).isEmpty
            ? 'Check this value.'
            : idText(e.value),
    };
  }

  /// "Items, row 2, Item: This field is required." for a key the form screen
  /// has no field for.
  static String describe(FormDefinition def, String key, String message) {
    final parts = key.split('.');
    String caption(String name) =>
        def.captionOf(name) ?? def.sectionOf(name)?.caption ?? name;
    if (parts.length == 3) {
      final row = (int.tryParse(parts[1]) ?? 0) + 1;
      return '${caption(parts[0])}, row $row, ${caption(parts[2])}: $message';
    }
    return '${caption(parts.first)}: $message';
  }
}
