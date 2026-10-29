import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/models/form_definition.dart';
import '../../../data/models/form_option.dart';
import '../../../data/models/ids.dart';

/// One field being filled: its value, its text editor (for the types that
/// are typed) and its error. A row of a grid section has its own set.
class FieldInput {
  FieldInput(this.def, Object? initial)
    : value = Rxn<Object?>(initial),
      text = TextEditingController(text: _textOf(initial)),
      focus = FocusNode();

  final FormFieldDef def;
  final Rxn<Object?> value;
  final TextEditingController text;
  final FocusNode focus;
  final error = RxnString();
  final key = GlobalKey();

  /// The choices of a list that takes them from the organisation.
  final choices = Rxn<List<FormChoice>>();
  final isLoadingChoices = false.obs;
  final hasChoicesFailed = false.obs;

  static String _textOf(Object? v) {
    if (v == null) return '';
    if (v is Map) {
      final lat = idText(v['lat']);
      final lng = idText(v['lng']);
      return lat.isEmpty || lng.isEmpty ? '' : '$lat, $lng';
    }
    return v is List ? '' : idText(v);
  }

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

/// One row of a grid section.
class RowInput {
  RowInput(this.fields) : id = _next++;

  static int _next = 0;

  final int id;
  final Map<String, FieldInput> fields;

  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
  }
}

/// A grid section: rows the person adds and removes.
class GridInput {
  GridInput(this.section, this.columns);

  final FormSectionDef section;
  final List<FormFieldDef> columns;
  final rows = <RowInput>[].obs;
  final error = RxnString();
  final key = GlobalKey();

  void dispose() {
    for (final r in rows) {
      r.dispose();
    }
  }
}
