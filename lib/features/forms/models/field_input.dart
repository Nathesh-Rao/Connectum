import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../data/models/form_definition.dart';
import '../../../data/models/form_option.dart';
import '../../../data/models/ids.dart';
import '../../../data/models/slot_day.dart';

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

  /// The source is waiting for the fields it takes its parameters from; these
  /// are their captions.
  final waitingFor = <String>[].obs;

  /// Where the choices came from: false for the definition's own copy used
  /// because the server could not be asked.
  bool isFreshChoices = false;

  /// The list shown is a kept copy, used because the server could not be
  /// asked: the field says it may be out of date.
  final isStaleChoices = false.obs;

  /// A quiet line under a field that fills itself ("Will fill when you're
  /// online").
  final note = RxnString();

  /// The value a fetch put here last, and the parameters it was asked with.
  String? lastFetched;
  String? fetchKey;
  Timer? fetchTimer;
  int fetchRun = 0;
  Timer? choicesTimer;
  int choicesRun = 0;

  /// Files of a file field, uploaded or uploading.
  final files = <FormFileItem>[].obs;

  /// The days a booking field offers, for the person it names.
  final slotDays = Rxn<List<SlotDay>>();
  final isLoadingSlots = false.obs;
  final slotError = RxnString();
  String? slotPerson;

  static String _textOf(Object? v) {
    if (v == null) return '';
    if (v is Map) {
      if (v.containsKey('amount')) return idText(v['amount']);
      final lat = idText(v['lat']);
      final lng = idText(v['lng']);
      return lat.isEmpty || lng.isEmpty ? '' : '$lat, $lng';
    }
    return v is List ? '' : idText(v);
  }

  /// Puts a value in that did not come from the keyboard (a fetch, a fill),
  /// and into the editor of a typed field.
  void apply(Object? v) {
    value.value = v;
    final shown = _textOf(v);
    if (text.text != shown) text.text = shown;
  }

  void dispose() {
    choicesTimer?.cancel();
    fetchTimer?.cancel();
    for (final f in files) {
      f.cancel.cancel();
    }
    text.dispose();
    focus.dispose();
  }
}

enum FormFileState { uploading, done, failed }

/// One file of a file field: its id once the server has it.
class FormFileItem {
  FormFileItem({
    required this.name,
    required this.size,
    this.path,
    this.mime = '',
    this.id,
  }) : state = (id == null ? FormFileState.uploading : FormFileState.done).obs;

  final String name;
  final int size;
  final String? path;
  final String mime;
  String? id;
  final Rx<FormFileState> state;
  final progress = 0.0.obs;
  final error = RxnString();
  CancelToken cancel = CancelToken();
}

/// One row of a grid section.
class RowInput {
  RowInput(this.fields) : id = _next++;

  static int _next = 0;

  final int id;
  final Map<String, FieldInput> fields;

  /// What the form put in when the row opened (defaults). A row that holds
  /// only this is not a row: nobody filled it in.
  final prefilled = <String, Object?>{};

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
