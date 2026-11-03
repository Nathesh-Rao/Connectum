import 'dart:convert';

import '../../data/models/form_definition.dart';
import '../../data/models/ids.dart';
import 'form_formats.dart';

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
    'toggle',
    'list',
    'location',
    'autogenerate',
    'barcode',
    'file',
    'selection',
    'fill',
    'payment',
    'slot',
  };

  static bool isSupported(FormFieldDef f) => supportedTypes.contains(f.type);

  /// The single-value kinds that can fill themselves from a fetch.
  static const fetchTypes = {
    'text',
    'email',
    'url',
    'mobile',
    'wholenumber',
    'number',
    'date',
    'time',
  };

  /// A field that asks the server for its value from other fields.
  static bool hasFetch(FormFieldDef f) =>
      fetchTypes.contains(f.type) &&
      f.raw['fetch'] is Map &&
      (f.raw['fetch']['type'] == 'query' || f.raw['fetch']['type'] == 'api');

  /// The payment methods of a field, in the form's own spelling.
  static List<String> methodsOf(FormFieldDef f) {
    final listed = f.raw['methods'];
    final methods = [
      if (listed is List)
        for (final m in listed)
          if (idText(m).isNotEmpty) idText(m),
    ];
    return methods.isEmpty ? const ['Cash', 'Card', 'UPI'] : methods;
  }

  /// How many files a file field takes.
  static int maxFiles(FormFieldDef f) => f.isMulti ? 10 : 1;

  /// Made for the person (an auto value, a fetch, a fill, a number the
  /// system makes): hiding one only keeps it off the screen, it is still sent.
  static bool isMadeFor(FormFieldDef f) =>
      f.hasCalc ||
      f.raw['fetch'] != null ||
      f.type == 'autogenerate' ||
      f.type == 'fill';

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

  // ---- starting values ----------------------------------------------------------

  /// The value a new record starts with: the fixed default, else today for a
  /// date and now for a time (unless the field turns that off), clamped into
  /// its range. Null when there is none.
  static Object? startingValue(FormFieldDef f, DateTime now) {
    final fixed = f.defaultValue;
    switch (f.type) {
      case 'toggle':
        return idText(fixed) == 'Yes' ? 'Yes' : 'No';
      case 'text' || 'email' || 'url' || 'mobile' || 'wholenumber' || 'number':
        return fixed == null ? null : idText(fixed);
      case 'list':
        return !f.isMulti && fixed != null ? idText(fixed) : null;
      case 'payment':
        return f.raw['amount'] == null
            ? null
            : {'amount': idText(f.raw['amount']), 'status': 'pending'};
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
    if (f.type == 'toggle') return idText(saved) == 'Yes' ? 'Yes' : 'No';
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
      case 'selection':
        if (f.isMulti) {
          return saved is List
              ? [for (final e in saved) idText(e)]
              : idText(saved).isEmpty
              ? <String>[]
              : [idText(saved)];
        }
        return idText(saved);
      case 'file':
        return saved is List
            ? [for (final e in saved) idText(e)]
            : idText(saved).isEmpty
            ? null
            : [idText(saved)];
      case 'payment':
        return saved is Map
            ? {
                'amount': idText(saved['amount']),
                'method': idText(saved['method']),
                'status': idText(saved['status']).isEmpty
                    ? 'pending'
                    : idText(saved['status']),
              }
            : null;
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
  static final _url = RegExp(r'^https?://\S+$');
  static final _mobile = RegExp(r'^\+?[0-9]{7,15}$');

  /// The first problem with one value, in plain words (the server's own
  /// words where it has them), or null.
  static String? check(FormFieldDef f, Object? value) {
    if (!isFilled(value)) {
      return f.isRequired && isSent(f) && !f.hasCalc && f.type != 'toggle'
          ? 'This field is required.'
          : null;
    }
    final text = value is String ? value.trim() : '';
    switch (f.type) {
      case 'text' || 'barcode':
        return utf8.encode(value as String).length > FormFormats.maxText
            ? 'Too long (max ${FormFormats.maxText} characters).'
            : null;
      case 'email':
        return _email.hasMatch(text) ? null : 'Enter a valid email address.';
      case 'url':
        return _url.hasMatch(text) ? null : 'Enter a valid http(s) URL.';
      case 'mobile':
        final clean = FormFormats.mobileClean(text);
        if (!_mobile.hasMatch(clean)) return 'Enter a valid mobile number.';
        return f.raw['withCountryCode'] == true && !clean.startsWith('+')
            ? 'Include the country code, e.g. +91...'
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
        if (!RegExp(r'^\d{2}:\d{2}(:\d{2})?$').hasMatch(text)) {
          return 'Pick a time.';
        }
        if (f.minText.isNotEmpty && text.compareTo(f.minText) < 0) {
          return 'Must be at ${f.minText} or later.';
        }
        if (f.maxText.isNotEmpty && text.compareTo(f.maxText) > 0) {
          return 'Must be at ${f.maxText} or earlier.';
        }
        return null;
      case 'location':
        return locationOf(value) == null
            ? 'Enter latitude and longitude, like 12.97, 77.59.'
            : null;
      case 'selection':
        if (value is List && value.length > 50) {
          return 'Choose at most 50 items.';
        }
        return null;
      case 'file':
        final max = maxFiles(f);
        return value is List && value.length > max
            ? 'Attach at most $max ${max == 1 ? 'file' : 'files'}.'
            : null;
      case 'slot':
        return RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(text)
            ? null
            : 'Choose a time from the list.';
      case 'payment':
        return _payment(f, value);
    }
    return null;
  }

  static String? _payment(FormFieldDef f, Object? value) {
    if (value is! Map) return 'Enter the payment details.';
    final amount = num.tryParse(idText(value['amount']).trim());
    if (amount == null) return 'Enter the amount.';
    if (amount < 0) return 'The amount cannot be negative.';
    final status = idText(value['status']).isEmpty
        ? 'pending'
        : idText(value['status']);
    if (status != 'paid' && status != 'pending') {
      return 'Choose paid or pay later.';
    }
    final method = idText(value['method']).trim();
    if (method.isEmpty) {
      return status == 'paid' ? 'Choose how it was paid.' : null;
    }
    final listed = [for (final m in methodsOf(f)) m.toLowerCase()];
    return listed.contains(method.toLowerCase())
        ? null
        : 'Choose a payment method from the list.';
  }

  static String _n(num n) => n == n.truncate() ? '${n.truncate()}' : '$n';

  static String? _range(FormFieldDef f, num n) {
    if (f.min != null && n < f.min!) return 'Must be at least ${_n(f.min!)}.';
    if (f.max != null && n > f.max!) return 'Must be at most ${_n(f.max!)}.';
    return null;
  }

  /// `{lat, lng, address?}` from a map or "lat, lng" text; null when it isn't
  /// a place.
  static Map<String, dynamic>? locationOf(Object? v) {
    if (v is Map) {
      final lat = num.tryParse(idText(v['lat']));
      final lng = num.tryParse(idText(v['lng']));
      if (lat == null || lng == null) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
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
      case 'mobile':
        return FormFormats.mobileClean(idText(value));
      case 'location':
        return locationOf(value);
      case 'toggle':
        return idText(value) == 'Yes' ? 'Yes' : 'No';
      case 'list' || 'selection':
        return value is List
            ? [for (final e in value) idText(e)]
            : idText(value);
      case 'file':
        final ids = [for (final e in value as List) idText(e)];
        return f.isMulti ? ids : ids.first;
      case 'payment':
        final m = value as Map;
        final method = idText(m['method']).trim();
        final listed = [
          for (final x in methodsOf(f))
            if (x.toLowerCase() == method.toLowerCase()) x,
        ];
        return {
          'amount': num.tryParse(idText(m['amount']).trim()),
          if (listed.isNotEmpty) 'method': listed.first,
          'status': idText(m['status']).isEmpty ? 'pending' : m['status'],
        };
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

/// Dates are held as `yyyy-mm-dd` and shown as `dd/mm/yyyy` (the format the
/// logic reads them in); times are held and shown as `HH:MM`.
class FormDates {
  FormDates._();

  static String show(String iso, {bool isMonthFirst = false}) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
    if (m == null) return iso;
    return isMonthFirst ? '${m[2]}/${m[3]}/${m[1]}' : '${m[3]}/${m[2]}/${m[1]}';
  }
}
