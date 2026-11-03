import '../../data/models/ids.dart';
import 'form_rules.dart';

/// TEMPORARY. Conditions (`{field, op, value}`, `{all}`, `{any}`) are form
/// logic and must come from the web's JS bundle once the backend adds
/// condition evaluation to it. Until then this is the old `FormRules.matches`,
/// moved here unchanged. Do not fix or extend it; replace it. Its differences
/// from the web's `evalCondition` are listed as vectors on `/debug/forms`.
class TemporaryConditionEvaluator {
  TemporaryConditionEvaluator._();

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
        return FormRules.isFilled(actual);
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
    if (!FormRules.isFilled(actual) || actual is List || actual is Map) {
      return false;
    }
    final a = idText(actual).trim();
    final e = idText(expected).trim();
    final x = num.tryParse(a);
    final y = num.tryParse(e);
    return test(x != null && y != null ? x.compareTo(y) : a.compareTo(e));
  }
}
