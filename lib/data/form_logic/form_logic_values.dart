import '../models/ids.dart';

/// The one place where the form's values are put into the shape the logic
/// reads (`FORM_LOGIC_FOR_MOBILE.md` section 3): dates `yyyy-mm-dd`, times
/// `HH:MM`, numbers without commas, a switch as `Yes`/`No`, a multi list as
/// comma text. Objects (a place, a payment) are passed on; the logic leaves
/// them out. The `dd/mm/yyyy` the parser wants is made inside the logic.
class FormLogicValues {
  FormLogicValues._();

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
  static final _time = RegExp(r'^(\d{1,2}):(\d{2})(:\d{2})?$');
  static const _yes = {'yes', 'y', 'true', 't', 'on', '1'};
  static const _no = {'no', 'n', 'false', 'f', 'off', '0'};

  /// [fields] are the form's field maps (ordinary and grid), [grids] the names
  /// of the grid sections; the rows of a grid are converted by column.
  static Map<String, dynamic> toLogic(
    List<Map<String, dynamic>> fields,
    Set<String> grids,
    Map<String, dynamic> values,
  ) {
    final types = {
      for (final f in fields)
        idText(f['name']): idText(f['type']).toLowerCase(),
    };
    final out = <String, dynamic>{};
    values.forEach((name, v) {
      if (grids.contains(name) && v is List) {
        out[name] = [
          for (final row in v)
            if (row is Map)
              {
                for (final e in row.entries)
                  idText(e.key): value(types[idText(e.key)] ?? '', e.value),
              }
            else
              row,
        ];
      } else {
        out[name] = value(types[name] ?? '', v);
      }
    });
    return out;
  }

  /// One value of a field of [type] (lower case, as the definition names it).
  static Object? value(String type, Object? v) {
    if (v == null) return null;
    switch (type) {
      case 'wholenumber' || 'number':
        if (v is num) return v;
        return idText(v).replaceAll(RegExp(r'[,\s]'), '');
      case 'date':
        return _date(idText(v).trim());
      case 'time':
        return _timeOf(idText(v).trim());
      case 'toggle':
        final t = idText(v).trim().toLowerCase();
        if (_yes.contains(t)) return 'Yes';
        if (_no.contains(t)) return 'No';
        return t.isEmpty ? '' : idText(v);
      default:
        if (v is List) return v.map(idText).join(',');
        return v;
    }
  }

  static String _date(String t) {
    if (_isoDate.hasMatch(t)) return t;
    final dmy = _dmy.firstMatch(t);
    if (dmy != null) {
      return '${dmy[3]}-${dmy[2]!.padLeft(2, '0')}-${dmy[1]!.padLeft(2, '0')}';
    }
    if (t.length > 10 && _isoDate.hasMatch(t.substring(0, 10))) {
      return t.substring(0, 10);
    }
    return t;
  }

  static String _timeOf(String t) {
    final m = _time.firstMatch(t);
    return m == null ? t : '${m[1]!.padLeft(2, '0')}:${m[2]}';
  }
}
