import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/data/socket/socket.dart';
import '../smart_view/models/sv_source.dart';
import 'smart_view_repository.dart';

/// One field a condition can filter by: its name, its caption from the form
/// definition and the kind the filter treats it as (`text`, `number`, `date`,
/// `bool`).
class InboxFieldInfo {
  const InboxFieldInfo({
    required this.name,
    required this.caption,
    required this.kind,
  });

  final String name;
  final String caption;
  final String kind;
}

/// Where the field kinds stand.
enum InboxKindsState { idle, loading, ready, failed }

/// The field kinds of the forms for the Advanced filter's conditions
/// (`FilterBlocks.jsx` `fieldsOf`, `columnType`). They come from the source
/// list (`ai.enterprise {what:"forms"}`) that [SmartViewRepository] reads
/// through the shared `ReadGate` and keeps in memory until the organisation
/// changes, so this class holds no copy of its own: a second [load] is no
/// read. Nothing is read until [load] is called.
class InboxFieldKinds {
  InboxFieldKinds(this._sources);

  final SmartViewRepository _sources;

  /// Where the last [load] stands (the panel shows it).
  final state = InboxKindsState.idle.obs;

  /// Reads the source list when it is not held yet. Returns true when the
  /// kinds are known; false when the read failed (the panel then says the
  /// conditions are not available).
  Future<bool> load() async {
    if (_sources.keptSources != null) {
      state.value = InboxKindsState.ready;
      return true;
    }
    state.value = InboxKindsState.loading;
    try {
      await _sources.sources();
      state.value = InboxKindsState.ready;
      return true;
    } on SocketCallError catch (e) {
      AppLog.w('inbox_field_kinds', 'sources not read: ${e.code}');
      state.value = InboxKindsState.failed;
      return false;
    } catch (e, st) {
      AppLog.e('inbox_field_kinds', e, st, 'sources unreadable');
      state.value = InboxKindsState.failed;
      return false;
    }
  }

  /// The kind of a column type as the filter treats it (`columnType` then
  /// `kindOfType`): number and whole number are number; date and slot are
  /// date; toggle is bool; everything else is text.
  static String kindOfFieldType(String? type) => switch (type) {
    'number' || 'wholenumber' => 'number',
    'date' || 'slot' => 'date',
    'toggle' => 'bool',
    _ => 'text',
  };

  SvSource? _sourceOf(String form) {
    final all = _sources.keptSources;
    if (all == null) return null;
    final want = form.trim().toLowerCase();
    for (final s in all) {
      if (s.name.toLowerCase() == want) return s;
    }
    return null;
  }

  /// The fields of [form] a condition may use, in the form's order. Empty
  /// when the kinds are not known or the form is not in the list.
  List<InboxFieldInfo> fieldsOf(String form) {
    final s = _sourceOf(form);
    if (s == null) return const [];
    return [
      for (final f in s.fields)
        InboxFieldInfo(
          name: f.name,
          caption: f.caption,
          kind: kindOfFieldType(f.type),
        ),
    ];
  }

  /// The kind of one field of [form]; text when it is not known.
  String kindOf(String form, String field) {
    for (final f in fieldsOf(form)) {
      if (f.name == field) return f.kind;
    }
    return 'text';
  }

  /// The column type of one field of [form] (`date`, `file`...) when the
  /// source list is already held; null otherwise. Never reads.
  String? typeOf(String form, String field) {
    final s = _sourceOf(form);
    if (s == null) return null;
    for (final f in s.fields) {
      if (f.name == field) return f.type;
    }
    return null;
  }
}
