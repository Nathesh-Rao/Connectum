import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:dio/dio.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/form_logic/form_logic_service.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/models/form_definition.dart';
import '../../data/models/form_option.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import 'form_rules.dart';
import 'temporary_condition_evaluator.dart';
import 'models/field_input.dart';
import 'models/form_launch.dart';

/// One open form: the answers, the checks and the send. It lives under the
/// launch's own tag, so two forms never share one. A form keeps its own copy
/// of the organisation and user it was opened in; if they change underneath
/// it, nothing is sent.
class FormController extends GetxController {
  FormController({
    required this.launch,
    required this.submissions,
    required this.options,
    required this.store,
    required this.connectivity,
    required this.logic,
    required this.files,
  });

  static const maxRows = 200;

  final FormLaunch launch;
  final SubmissionRepository submissions;
  final FormOptionsRepository options;
  final SessionStore store;
  final ConnectivityService connectivity;
  final FormLogicService logic;
  final FormFileRepository files;

  final viewState = AppViewState.loading.obs;
  final isSubmitting = false.obs;
  final banner = RxnString();
  final hasBlockingField = false.obs;

  /// Without a connection: the captions of the fields that fill themselves
  /// from the server and are still empty, and whether this save may be kept
  /// as a draft. Sending waits until the first list is empty.
  final waitingNames = <String>[].obs;
  final canSaveDraft = false.obs;
  final scroll = ScrollController();

  /// Fixed for this opening: the sending refuses to run if these changed.
  late final String _org = store.orgId ?? '';
  late final String _user = store.userId ?? '';

  /// One id for this opening's save: a second tap on Done reuses it, so the
  /// server saves once.
  final cid = newCid();

  FormDefinition? definition;
  final fields = <String, FieldInput>{};
  final grids = <String, GridInput>{};
  String _initial = '';
  bool _isClosing = false;
  bool _isDisposed = false;
  Worker? _onlineWorker;
  FormShape? _shape;
  Timer? _calcTimer;
  int _calcRun = 0;
  bool _isMonthFirst = false;

  static const calcDelay = Duration(milliseconds: 150);
  static const sourceDelay = Duration(milliseconds: 250);

  /// The last typed field of the form: its action key finishes the typing.
  FieldInput? lastTyped;

  /// Does any field read another (a selection, a fill, a fetch, a booking
  /// time)? When none does, a change needs no looking around.
  bool _hasSources = false;

  /// How a date is shown (`dd/mm/yyyy` unless the form says otherwise); it is
  /// always held and sent as `yyyy-mm-dd`.
  bool get isMonthFirst => _isMonthFirst;

  bool get isOffline => connectivity.state.value != AppConnectivity.online;

  /// A list with nothing kept can't be asked: it says so instead of offering
  /// a retry. The sample data always says so, to be seen without a server.
  bool get isConnectNeeded => isOffline || SeedUi.isActive;

  bool get isEncryptedChat => launch.convId != null && launch.isEncryptedChat;

  bool get isDirty => definition != null && _snapshot() != _initial;

  @override
  void onInit() {
    super.onInit();
    // A form that couldn't be opened offline tries again when the network
    // returns.
    _onlineWorker = ever(connectivity.state, (state) {
      _updateDraftState();
      if (state != AppConnectivity.online) return;
      if (viewState.value == AppViewState.offline) unawaited(_load());
      if (definition != null) _refreshSources();
    });
    unawaited(_load());
  }

  Future<void> retry() => _load();

  Future<void> _load() async {
    viewState.value = AppViewState.loading;
    final isOnline = connectivity.state.value == AppConnectivity.online;
    final def = await submissions.definition(launch.name, scope: launch.scope);
    if (def == null || !def.isFull) {
      viewState.value = isOnline ? AppViewState.error : AppViewState.offline;
      return;
    }
    if (_isDisposed || definition != null) return;
    definition = def;
    _hasSources = def.fields.any(
      (f) =>
          f.type == 'selection' ||
          f.type == 'fill' ||
          f.type == 'slot' ||
          FormRules.hasFetch(f),
    );
    _shape = FormShape(def.raw);
    _isMonthFirst = idText(def.raw['dateFormat']).toLowerCase() == 'mm/dd/yyyy';
    await logic.setDateFormat(_isMonthFirst ? 'mm/dd/yyyy' : 'dd/mm/yyyy');
    _build(def);
    _startSources();
    await _calc();
    if (_isDisposed) return;
    _initial = _snapshot();
    if (launch.errorDetails != null) showServerErrors(launch.errorDetails);
    unawaited(options.markUsed(launch.name, def.scope, def.caption));
    _updateDraftState();
    viewState.value = AppViewState.content;
  }

  void _build(FormDefinition def) {
    final now = DateTime.now();
    final saved = launch.savedValues;
    final isEdit = launch.isEdit && saved != null;
    for (final f in def.fields) {
      if (def.isGridSection(f.section)) continue;
      final initial = isEdit
          ? FormRules.fromSaved(f, saved[f.name])
          : FormRules.startingValue(f, now);
      final input = FieldInput(f, initial);
      fields[f.name] = input;
    }
    for (final input in fields.values) {
      _prepare(input);
    }
    lastTyped = _lastTypedOf(def);
    for (final s in def.sections) {
      if (!s.isGrid) continue;
      final columns = [
        for (final c in def.columnsOf(s.name))
          if (c.raw['hidden'] != true) c,
      ];
      final grid = GridInput(s, columns);
      final savedRows = isEdit ? saved[s.name] : null;
      if (savedRows is List) {
        for (final row in savedRows) {
          if (row is Map) grid.rows.add(_row(columns, row, now, isSaved: true));
        }
      }
      if (grid.rows.isEmpty) {
        grid.rows.add(_row(columns, const {}, now, isSaved: false));
      }
      grids[s.name] = grid;
    }
    hasBlockingField.value = def.fields.any(
      (f) => f.isRequired && !FormRules.isSupported(f) && !f.hasCalc,
    );
    if (hasBlockingField.value) {
      banner.value =
          "This form has a required field mobile can't fill yet, so it can't be sent from here.";
    }
  }

  RowInput _row(
    List<FormFieldDef> columns,
    Map saved,
    DateTime now, {
    required bool isSaved,
  }) {
    final row = RowInput({
      for (final c in columns)
        c.name: FieldInput(
          c,
          isSaved
              ? FormRules.fromSaved(c, saved[c.name])
              : FormRules.startingValue(c, now),
        ),
    });
    if (!isSaved) {
      row.fields.forEach((name, input) {
        row.prefilled[name] = input.value.value;
      });
    }
    for (final input in row.fields.values) {
      _prepare(input, row: row);
    }
    return row;
  }

  // ---- what is shown --------------------------------------------------------------

  Object? _valueOf(String name, RowInput? row) {
    final inRow = row?.fields[name];
    if (inRow != null) return inRow.value.value;
    return fields[name]?.value.value;
  }

  /// A field is shown when it is not hidden and its own condition and its
  /// section's both hold. A grid field's condition looks at its own row
  /// first. Reads the values it depends on, so an Obx around it rebuilds when
  /// they change.
  bool isVisible(FormFieldDef f, {RowInput? row}) =>
      definition != null && f.raw['hidden'] != true && _isCounted(f, row: row);

  /// Does the field take part (conditions hold), shown or not?
  bool _isCounted(FormFieldDef f, {RowInput? row}) {
    final def = definition;
    if (def == null) return false;
    final section = def.sectionOf(f.section);
    if (section != null &&
        !TemporaryConditionEvaluator.matches(
          section.condition,
          (n) => _valueOf(n, null),
        )) {
      return false;
    }
    return TemporaryConditionEvaluator.matches(
      f.condition,
      (n) => _valueOf(n, row),
    );
  }

  /// Does the value go into the record? What is shown does; so does a hidden
  /// field made for the person (calc, fetch, fill), which only stays off the
  /// screen.
  bool _isSent(FormFieldDef f, {RowInput? row}) =>
      f.raw['hidden'] == true && FormRules.isMadeFor(f)
      ? _isCounted(f, row: row)
      : isVisible(f, row: row);

  /// True when showing this field depends on other answers (its own
  /// condition or its section's). Only those need to watch values.
  bool hasCondition(FormFieldDef f) =>
      f.condition != null ||
      definition?.sectionOf(f.section)?.condition != null;

  bool get hasSectionConditions =>
      definition?.sections.any((s) => s.condition != null) ?? false;

  bool isSectionVisible(FormSectionDef s) =>
      TemporaryConditionEvaluator.matches(
        s.condition,
        (n) => _valueOf(n, null),
      );

  /// The sections to show, in order, with those whose condition fails left
  /// out. Reads the values the conditions depend on.
  List<String> visibleSections() {
    final def = definition;
    if (def == null) return const [];
    return [
      for (final name in def.sectionOrder)
        if (name.isEmpty || isSectionVisible(def.sectionOf(name)!)) name,
    ];
  }

  // ---- editing -----------------------------------------------------------------------

  void setValue(FieldInput f, Object? value, {RowInput? row}) {
    f.value.value = value;
    if (f.error.value != null) f.error.value = null;
    if (banner.value != null && !hasBlockingField.value) banner.value = null;
    _refitDependents(f, row);
    _afterChange(f, row);
    _scheduleCalc();
    _updateDraftState();
  }

  /// A cascading list drops its value when the list it depends on changes
  /// and the value no longer fits.
  void _refitDependents(FieldInput changed, RowInput? row) {
    final inputs = row?.fields ?? fields;
    for (final other in inputs.values) {
      final dep = other.def.raw['dependsOn'];
      if (dep is! Map || idText(dep['field']) != changed.def.name) continue;
      final shown = shownChoices(other, row: row);
      final value = other.value.value;
      if (shown == null || value == null) continue;
      final fits = {for (final c in shown) c.value};
      if (value is List) {
        final keep = [
          for (final e in value)
            if (fits.contains(idText(e))) e,
        ];
        if (keep.length != value.length) setValue(other, keep, row: row);
      } else if (!fits.contains(idText(value))) {
        setValue(other, null, row: row);
      }
    }
  }

  /// The choices a list offers now. A list that depends on another field
  /// offers what the server marked for that field's value (`optionProps`),
  /// nothing until that field is filled.
  List<FormChoice>? shownChoices(FieldInput input, {RowInput? row}) {
    final all = input.choices.value;
    final dep = input.def.raw['dependsOn'];
    if (all == null || dep is! Map || input.def.options.isEmpty) return all;
    final have = idText(_valueOf(idText(dep['field']), row)).trim();
    if (have.isEmpty) return const [];
    final props = input.def.raw['optionProps'];
    bool fits(Object? prop) => [
      for (final p in prop is List ? prop : [prop])
        idText(p).trim().toLowerCase(),
    ].contains(have.toLowerCase());
    return [
      for (final c in all)
        if (fits(props is Map ? props[c.value] : null)) c,
    ];
  }

  RowInput? addRow(GridInput grid) {
    if (grid.rows.length >= maxRows) return null;
    final row = _row(grid.columns, const {}, DateTime.now(), isSaved: false);
    grid.rows.add(row);
    grid.error.value = null;
    _scheduleCalc();
    return row;
  }

  void removeRow(GridInput grid, RowInput row) {
    grid.rows.remove(row);
    // The row's editors are still on screen until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
    _scheduleCalc();
  }

  // ---- sources: selection, fill, fetch, files, slots, payment --------------------

  static const _typedKinds = {
    'text',
    'email',
    'url',
    'mobile',
    'wholenumber',
    'number',
    'barcode',
  };

  FieldInput? _lastTypedOf(FormDefinition def) {
    FieldInput? last;
    for (final f in def.fields) {
      final input = fields[f.name];
      if (input == null || f.raw['hidden'] == true) continue;
      if (f.hasCalc || f.isReadOnly) continue;
      if (_typedKinds.contains(f.type)) last = input;
    }
    return last;
  }

  /// Starts what a field needs on its own when the form opens.
  void _prepare(FieldInput input, {RowInput? row}) {
    switch (input.def.type) {
      case 'list':
        unawaited(loadChoices(input));
      case 'selection':
        unawaited(loadSelection(input, row: row));
      case 'file':
        final ids = input.value.value;
        if (ids is List) {
          for (final id in ids) {
            input.files.add(
              FormFileItem(name: 'Attached file', size: 0, id: idText(id)),
            );
          }
        }
    }
  }

  void _startSources() {
    for (final input in fields.values) {
      if (FormRules.hasFetch(input.def)) _scheduleFetch(input);
    }
  }

  /// The network is back: what could not be asked is asked again.
  void _refreshSources() {
    final pairs = <(FieldInput, RowInput?)>[
      for (final i in fields.values) (i, null),
      for (final g in grids.values)
        for (final r in g.rows)
          for (final i in r.fields.values) (i, r),
    ];
    for (final (input, row) in pairs) {
      if (input.def.type == 'selection' &&
          (input.hasChoicesFailed.value || input.isStaleChoices.value)) {
        unawaited(loadSelection(input, row: row));
      }
      if (input.def.type == 'list' && input.hasChoicesFailed.value) {
        unawaited(retryChoices(input));
      }
      if (row == null &&
          FormRules.hasFetch(input.def) &&
          input.note.value != null) {
        input.fetchKey = null;
        _scheduleFetch(input);
      }
    }
  }

  Map? _params(FormFieldDef f, String key) {
    final holder = f.raw[key];
    final params = holder is Map ? holder['params'] : null;
    return params is Map ? params : null;
  }

  /// The ids of the fields a source takes its parameters from.
  List<String> _paramFields(FormFieldDef f, String key) => [
    for (final spec in (_params(f, key)?.values ?? const []))
      if (spec is Map && spec['field'] != null && spec['value'] == null)
        idText(spec['field']),
  ];

  /// The values the server needs to answer (it reads them by the field the
  /// parameter is taken from), and the captions of the fields still empty.
  (Map<String, dynamic>, List<String>) _sourceValues(
    FormFieldDef f,
    String key, {
    RowInput? row,
  }) {
    final values = <String, dynamic>{};
    final waiting = <String>[];
    for (final spec in (_params(f, key)?.values ?? const [])) {
      if (spec is! Map || spec['field'] == null) continue;
      final id = idText(spec['field']);
      final v = _valueOf(id, row);
      if (!FormRules.isFilled(v)) {
        if (spec['optional'] == true) {
          values[id] = '';
        } else {
          waiting.add(definition?.captionOf(id) ?? id);
        }
      } else {
        values[id] = v is List ? [for (final e in v) idText(e)] : idText(v);
      }
    }
    return (values, waiting);
  }

  /// What a selection field offers: from the server (`form.options`), else the
  /// choices the definition carries. Nothing is asked while a field it
  /// depends on is empty.
  Future<void> loadSelection(FieldInput f, {RowInput? row}) async {
    final def = definition;
    final source = f.def.raw['source'];
    if (def == null || source is! Map) return;
    final run = ++f.choicesRun;
    final (values, waiting) = _sourceValues(f.def, 'source', row: row);
    if (waiting.isNotEmpty) {
      f.choices.value = null;
      f.hasChoicesFailed.value = false;
      f.isLoadingChoices.value = false;
      f.waitingFor.assignAll(waiting);
      return;
    }
    f.waitingFor.clear();
    f.isLoadingChoices.value = true;
    f.hasChoicesFailed.value = false;
    final res = await options.fieldRows(
      form: launch.name,
      scope: def.scope,
      field: f.def.name,
      values: values,
      rev: def.rev,
    );
    if (_isDisposed || run != f.choicesRun) return;
    f.isLoadingChoices.value = false;
    if (res == null) {
      // Nothing kept for these exact values (or too old): the field waits for
      // a connection rather than offering another parent's list.
      f.choices.value = null;
      f.isStaleChoices.value = false;
      f.hasChoicesFailed.value = true;
      return;
    }
    if (res.isWaiting) {
      f.choices.value = null;
      f.waitingFor.assignAll(
        _paramFields(f.def, 'source').map((id) => def.captionOf(id) ?? id),
      );
      return;
    }
    f.isFreshChoices = !res.isStale;
    f.isStaleChoices.value = res.isStale;
    f.choices.value = res.choices;
    if (!res.isTruncated && !res.isStale) _dropUnoffered(f, res.choices, row);
    _refill(f, row);
  }

  Future<void> retrySelection(FieldInput f, {RowInput? row}) =>
      loadSelection(f, row: row);

  /// A chosen value the source no longer offers is dropped; several keep the
  /// ones that are still on offer.
  void _dropUnoffered(FieldInput f, List<FormChoice> offered, RowInput? row) {
    final fits = {for (final c in offered) c.value};
    final value = f.value.value;
    if (value is List) {
      final keep = [
        for (final e in value)
          if (fits.contains(idText(e))) e,
      ];
      if (keep.length != value.length) setValue(f, keep, row: row);
    } else if (value != null &&
        idText(value).isNotEmpty &&
        !fits.contains(idText(value))) {
      // The server's message about this choice stays next to the field.
      final said = f.error.value;
      setValue(f, null, row: row);
      f.error.value ??= said;
    }
  }

  void _reloadSelection(FieldInput f, RowInput? row) {
    f.choicesTimer?.cancel();
    final (_, waiting) = _sourceValues(f.def, 'source', row: row);
    if (waiting.isNotEmpty) {
      unawaited(loadSelection(f, row: row));
      return;
    }
    f.choicesTimer = Timer(
      sourceDelay,
      () => unawaited(loadSelection(f, row: row)),
    );
  }

  /// Everything that reads [changed]: a selection that takes its parameters
  /// from it, a fill that copies from it, a fetch that asks with it, a
  /// booking time of the person it names.
  void _afterChange(FieldInput changed, RowInput? row) {
    if (!_hasSources) return;
    final name = changed.def.name;
    final pairs = <(FieldInput, RowInput?)>[
      if (row != null)
        for (final i in row.fields.values) (i, row),
      for (final i in fields.values) (i, null),
      if (row == null)
        for (final g in grids.values)
          for (final r in g.rows)
            for (final i in r.fields.values) (i, r),
    ];
    for (final (other, otherRow) in pairs) {
      if (identical(other, changed)) continue;
      final f = other.def;
      switch (f.type) {
        case 'selection':
          if (_paramFields(f, 'source').contains(name)) {
            _reloadSelection(other, otherRow);
          }
        case 'fill':
          if (idText(f.raw['fillFrom']) == name) {
            _fill(other, changed, otherRow);
          }
        case 'slot':
          if (idText(f.raw['of']) == name) {
            other.slotDays.value = null;
            other.slotPerson = null;
            if (other.value.value != null) setValue(other, null, row: otherRow);
          }
        default:
          if (otherRow == null &&
              FormRules.hasFetch(f) &&
              _paramFields(f, 'fetch').contains(name)) {
            _scheduleFetch(other);
          }
      }
    }
  }

  // ---- fill ----

  /// Copies the property of the chosen record into a fill field. Several
  /// chosen at once copy nothing.
  void _fill(FieldInput fill, FieldInput from, RowInput? row) {
    final v = from.value.value;
    if (v is List) return;
    final picked = idText(v);
    if (picked.isEmpty) {
      fill.apply(null);
      return;
    }
    final choice = from.choices.value
        ?.where((c) => c.value == picked)
        .firstOrNull;
    if (choice == null) return;
    final prop = idText(fill.def.raw['sourceProp']);
    final raw = choice.raw;
    final got = raw == null
        ? ''
        : idText(raw[prop.isEmpty ? 'value' : prop] ?? raw['name']);
    fill.apply(got.isEmpty ? null : got);
    fill.error.value = null;
  }

  /// A selection's choices arrived: the fill fields that copy from it and are
  /// still empty are filled.
  void _refill(FieldInput from, RowInput? row) {
    final inputs = row?.fields ?? fields;
    for (final other in inputs.values) {
      if (other.def.type == 'fill' &&
          idText(other.def.raw['fillFrom']) == from.def.name &&
          !FormRules.isFilled(other.value.value)) {
        _fill(other, from, row);
      }
    }
  }

  // ---- fetch ----

  /// A field that fills itself asks again whenever a field it depends on
  /// changes. A value the person typed is never overruled: the answer only
  /// replaces an empty value or the one a fetch put there.
  void _scheduleFetch(FieldInput f) {
    final (values, waiting) = _sourceValues(f.def, 'fetch');
    final key = jsonEncode(values);
    if (f.fetchKey == key && waiting.isEmpty) return;
    final first = f.fetchKey == null;
    f.fetchKey = waiting.isEmpty ? key : '';
    f.fetchTimer?.cancel();
    final run = ++f.fetchRun;
    if (waiting.isNotEmpty) {
      f.waitingFor.assignAll(waiting);
      f.note.value = null;
      if (!first) _settleFetch(f, null);
      return;
    }
    f.waitingFor.clear();
    if (connectivity.state.value != AppConnectivity.online) {
      f.note.value = "Will fill when you're online";
      f.fetchKey = null;
      return;
    }
    f.note.value = null;
    f.fetchTimer = Timer(sourceDelay, () async {
      final def = definition;
      if (def == null) return;
      final res = await options.fieldRows(
        form: launch.name,
        scope: def.scope,
        field: f.def.name,
        values: values,
        limit: 1,
        rev: def.rev,
      );
      if (_isDisposed || run != f.fetchRun) return;
      if (res == null) {
        f.note.value = "Will fill when you're online";
        f.fetchKey = null;
        return;
      }
      if (res.isWaiting) return;
      _settleFetch(f, _fetched(f.def, res.choices.firstOrNull));
    });
  }

  /// The row's value made to fit the field: a number or nothing for a number
  /// field, text as it is otherwise.
  String? _fetched(FormFieldDef f, FormChoice? row) {
    final raw = row == null ? '' : idText(row.value);
    if (raw.isEmpty) return null;
    if (f.type == 'number' || f.type == 'wholenumber') {
      final n = num.tryParse(raw.trim());
      if (n == null || !n.isFinite) return null;
      if (f.type == 'wholenumber' && n != n.truncate()) return null;
      return f.type == 'wholenumber' ? '${n.truncate()}' : raw.trim();
    }
    return raw;
  }

  void _settleFetch(FieldInput f, String? found) {
    final current = idText(f.value.value);
    final isMine =
        current.isEmpty || (f.lastFetched != null && current == f.lastFetched);
    if (!isMine) return;
    final next = found ?? '';
    f.lastFetched = found;
    if (current == next) return;
    f.apply(next.isEmpty ? null : next);
    f.error.value = null;
    _scheduleCalc();
    _updateDraftState();
  }

  // ---- booking times ----

  Future<void> loadSlots(FieldInput f, {RowInput? row}) async {
    final person = idText(_valueOf(idText(f.def.raw['of']), row));
    if (person.isEmpty) return;
    if (f.slotPerson == person && f.slotDays.value != null) return;
    f.isLoadingSlots.value = true;
    f.slotError.value = null;
    final days = await options.slots(person);
    if (_isDisposed) return;
    f.isLoadingSlots.value = false;
    if (days == null) {
      f.slotError.value = 'Needs a connection to load the times';
      return;
    }
    f.slotPerson = person;
    f.slotDays.value = days;
  }

  /// The caption of the field a booking time names, for "Choose X first".
  String slotOfCaption(FormFieldDef f) =>
      definition?.captionOf(idText(f.raw['of'])) ?? idText(f.raw['of']);

  bool hasSlotPerson(FormFieldDef f, {RowInput? row}) =>
      idText(_valueOf(idText(f.raw['of']), row)).isNotEmpty;

  // ---- payment ----

  void setPayment(
    FieldInput f, {
    String? amount,
    String? method,
    String? status,
    RowInput? row,
  }) {
    final cur = f.value.value is Map ? f.value.value as Map : const {};
    final next = {
      'amount': amount ?? idText(cur['amount']),
      'method': method ?? idText(cur['method']),
      'status':
          status ??
          (idText(cur['status']).isEmpty ? 'pending' : idText(cur['status'])),
    };
    final isBlank =
        idText(next['amount']).isEmpty &&
        idText(next['method']).isEmpty &&
        next['status'] == 'pending';
    setValue(f, isBlank ? null : next, row: row);
  }

  // ---- files ----

  /// Picks a file, checks it the way a chat attachment is checked, and
  /// uploads it. Attaching needs a connection.
  Future<void> addFile(FieldInput f, AttachSource source) async {
    f.error.value = null;
    if (connectivity.state.value != AppConnectivity.online) {
      f.error.value = 'Attaching a file needs a connection.';
      return;
    }
    final max = FormRules.maxFiles(f.def);
    if (f.def.isMulti && f.files.length >= max) {
      f.error.value = 'Attach at most $max files.';
      return;
    }
    final PickedAttachment? picked;
    try {
      picked = await files.pick(source);
    } on AttachmentException catch (e) {
      f.error.value = e.message;
      return;
    }
    if (picked == null || _isDisposed) return;
    if (!f.def.isMulti) {
      for (final old in f.files.toList()) {
        old.cancel.cancel();
      }
      f.files.clear();
    }
    final item = FormFileItem(
      name: picked.name,
      size: picked.bytes,
      path: picked.path,
      mime: picked.mime,
    );
    f.files.add(item);
    _syncFiles(f);
    unawaited(_upload(f, item));
  }

  Future<void> _upload(FieldInput f, FormFileItem item) async {
    item.state.value = FormFileState.uploading;
    item.error.value = null;
    item.progress.value = 0;
    try {
      final done = await files.upload(
        PickedAttachment(
          kind: 'file',
          path: item.path ?? '',
          name: item.name,
          mime: item.mime,
          bytes: item.size,
        ),
        onProgress: (p) => item.progress.value = p,
        cancel: item.cancel,
      );
      if (_isDisposed || !f.files.contains(item)) return;
      item.id = done.id;
      item.state.value = FormFileState.done;
    } on AttachmentException catch (e) {
      if (!f.files.contains(item)) return;
      item.error.value = e.message;
      item.state.value = FormFileState.failed;
    }
    _syncFiles(f);
  }

  void retryFile(FieldInput f, FormFileItem item) {
    item.cancel = CancelToken();
    unawaited(_upload(f, item));
  }

  void removeFile(FieldInput f, FormFileItem item) {
    item.cancel.cancel();
    f.files.remove(item);
    f.error.value = null;
    _syncFiles(f);
  }

  /// The ids of the files the server has; what is still uploading is not in
  /// the value yet.
  void _syncFiles(FieldInput f) {
    final ids = [
      for (final i in f.files)
        if (i.id != null && i.state.value == FormFileState.done) i.id!,
    ];
    f.value.value = ids.isEmpty ? null : ids;
    if (f.error.value != null && f.files.every((i) => i.error.value == null)) {
      f.error.value = null;
    }
    _updateDraftState();
  }

  String? _fileProblem(FieldInput f) {
    if (f.def.type != 'file') return null;
    if (f.files.any((i) => i.state.value == FormFileState.uploading)) {
      return 'Wait for the upload to finish.';
    }
    if (f.files.any((i) => i.state.value == FormFileState.failed)) {
      return "A file didn't upload. Retry it or remove it.";
    }
    return null;
  }

  // ---- calculations (the form logic runs in FormLogicService) ---------------------

  void _scheduleCalc() {
    _calcTimer?.cancel();
    _calcTimer = Timer(calcDelay, () => unawaited(_calc()));
  }

  /// The answers as the editor holds them, by field name; a grid is a list
  /// of its rows' cells, every row in place.
  Map<String, dynamic> _values() {
    final out = <String, dynamic>{};
    fields.forEach((name, input) {
      final v = input.value.value;
      if (v != null) out[name] = v;
    });
    for (final g in grids.entries) {
      out[g.key] = [
        for (final r in g.value.rows)
          {
            for (final e in r.fields.entries)
              if (e.value.value.value != null) e.key: e.value.value.value,
          },
      ];
    }
    return out;
  }

  /// Works out every auto value and puts the answers in the locked fields.
  /// False when the logic could not answer.
  Future<bool> _calc() async {
    final shape = _shape;
    if (shape == null || _isDisposed) return false;
    final run = ++_calcRun;
    final r = await logic.applyFormCalcs(
      shape.fields,
      shape.gridList,
      shape.toLogic(_values()),
    );
    if (_isDisposed) return false;
    if (run != _calcRun) return true;
    if (!r.isOk) return false;
    final res = r.value!;
    void put(FieldInput input, Object? v) {
      final t = idText(v);
      final next = t.isEmpty ? null : t;
      if (input.value.value != next) input.value.value = next;
    }

    fields.forEach((name, input) {
      if (input.def.hasCalc) put(input, res[name]);
    });
    for (final g in grids.values) {
      final rows = res[g.section.name];
      if (rows is! List) continue;
      for (var i = 0; i < g.rows.length && i < rows.length; i++) {
        final cells = rows[i];
        if (cells is! Map) continue;
        g.rows[i].fields.forEach((name, input) {
          if (input.def.hasCalc) put(input, cells[name]);
        });
      }
    }
    return true;
  }

  Future<void> loadChoices(FieldInput f) async {
    if (f.choices.value != null || f.isLoadingChoices.value) return;
    final source = f.def.source;
    if (f.def.options.isNotEmpty || source.isEmpty) {
      // A list that takes its names from the organisation, read from the
      // copy of the form kept on the phone: marked old while offline, and
      // unusable once that copy is older than two days.
      if (source.isNotEmpty && isOffline) {
        final fetched = definition?.fetchedTs ?? 0;
        if (fetched > 0 &&
            !FormOptionsRepository.isUsableOffline(
              fetched,
              DateTime.now().millisecondsSinceEpoch,
            )) {
          f.hasChoicesFailed.value = true;
          return;
        }
        f.isStaleChoices.value = true;
      }
      final labels = f.def.raw['optionLabels'];
      f.choices.value = [
        for (final o in f.def.options)
          FormChoice(
            o,
            labels is Map && labels[o] != null ? idText(labels[o]) : o,
          ),
      ];
      return;
    }
    f.isLoadingChoices.value = true;
    final list = await options.choicesFor(source);
    f.isLoadingChoices.value = false;
    f.hasChoicesFailed.value = list == null;
    if (list != null) f.choices.value = list;
  }

  Future<void> retryChoices(FieldInput f) {
    f.hasChoicesFailed.value = false;
    return loadChoices(f);
  }

  // ---- checking and building --------------------------------------------------------

  String _snapshot() {
    final parts = <String>[
      for (final e in fields.entries)
        '${e.key}=${jsonEncode(e.value.value.value)}',
      for (final g in grids.entries)
        '${g.key}=${jsonEncode([
          for (final r in g.value.rows) [for (final f in r.fields.values) f.value.value],
        ])}',
    ];
    return parts.join('|');
  }

  /// Nobody filled the row in: nothing in it, or only what the form put there.
  /// An auto value does not make a row filled in.
  bool _isRowEmpty(RowInput row) => row.fields.entries.every((e) {
    final f = e.value;
    if (FormRules.isMadeFor(f.def)) return true;
    final v = f.value.value;
    if (!FormRules.isFilled(v)) return true;
    return row.prefilled.containsKey(e.key) &&
        jsonEncode(row.prefilled[e.key]) == jsonEncode(v);
  });

  /// Marks every problem on screen and returns whether there were none. The
  /// rules run on submit only, in the logic, with every field of the form
  /// given (blank when empty).
  Future<bool> validate() async {
    final def = definition;
    final shape = _shape;
    if (def == null || shape == null) return false;
    final logicValues = shape.toLogic(_values());
    final blanksResult = await logic.withBlanks(shape.fieldIds, logicValues);
    if (!blanksResult.isOk) {
      banner.value = "The checks couldn't run. Try again.";
      return false;
    }
    final blanks = blanksResult.value!;
    GlobalKey? first;
    var isEngineDown = false;

    Future<String?> check(
      FormFieldDef f,
      FieldInput state,
      Map<String, dynamic> context,
      Object? logicValue,
    ) async {
      var message =
          _fileProblem(state) ?? FormRules.check(f, state.value.value);
      if (message == null &&
          f.raw['rule'] is Map &&
          FormRules.isFilled(state.value.value)) {
        final r = await logic.fieldRuleError(f.raw, logicValue, context);
        if (r.isOk) {
          message = r.value;
        } else {
          isEngineDown = true;
        }
      }
      state.error.value = message;
      if (message != null) first ??= state.key;
      return message;
    }

    for (final f in def.fields) {
      if (def.isGridSection(f.section)) continue;
      final state = fields[f.name]!;
      if (!isVisible(f)) {
        state.error.value = null;
        continue;
      }
      await check(f, state, blanks, logicValues[f.name]);
    }
    for (final g in grids.values) {
      g.error.value = null;
      final rowsLogic = logicValues[g.section.name] as List? ?? const [];
      for (var i = 0; i < g.rows.length; i++) {
        final row = g.rows[i];
        final isHidden = !isSectionVisible(g.section) || _isRowEmpty(row);
        final cells = i < rowsLogic.length && rowsLogic[i] is Map
            ? (rowsLogic[i] as Map).cast<String, dynamic>()
            : const <String, dynamic>{};
        final context = {
          ...blanks,
          for (final c in g.columns) c.name: '',
          ...cells,
        };
        for (final c in g.columns) {
          final state = row.fields[c.name]!;
          if (isHidden || !isVisible(c, row: row)) {
            state.error.value = null;
            continue;
          }
          await check(c, state, context, cells[c.name]);
        }
      }
    }
    if (isEngineDown) {
      banner.value = "Some checks couldn't run. Try again.";
      return false;
    }
    _scrollTo(first);
    return first == null;
  }

  void _scrollTo(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return;
    unawaited(
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
      ),
    );
  }

  /// What is sent: shown fields, and hidden ones made for the person (calc,
  /// fetch, fill); never an Auto Generate number or an empty value. A grid
  /// sends every row in place (a row nobody filled in is `{}`).
  Map<String, dynamic> buildValues() {
    final def = definition!;
    final out = <String, dynamic>{};
    for (final f in def.fields) {
      if (def.isGridSection(f.section)) continue;
      if (!_isSent(f)) continue;
      final v = FormRules.toSent(f, fields[f.name]!.value.value);
      if (v != null) out[f.name] = v;
    }
    for (final g in grids.values) {
      if (!isSectionVisible(g.section)) continue;
      out[g.section.name] = [for (final row in g.rows) _sentRow(g, row)];
    }
    return out;
  }

  Map<String, dynamic> _sentRow(GridInput g, RowInput row) {
    final cells = <String, dynamic>{};
    if (_isRowEmpty(row)) return cells;
    for (final c in g.columns) {
      if (!_isSent(c, row: row)) continue;
      final v = FormRules.toSent(c, row.fields[c.name]!.value.value);
      if (v != null) cells[c.name] = v;
    }
    return cells;
  }

  // ---- drafts ---------------------------------------------------------------------------

  /// Without a connection: fields that fill themselves from the server (a
  /// fetch, a fill) and are still empty.
  List<String> _waitingFields() {
    final def = definition;
    if (def == null || !isOffline) return const [];
    return [
      for (final f in def.fields)
        if (!def.isGridSection(f.section) &&
            fields[f.name] != null &&
            (FormRules.hasFetch(f) || f.type == 'fill') &&
            isVisible(f) &&
            !FormRules.isFilled(fields[f.name]!.value.value))
          f.caption,
    ];
  }

  /// Without a connection a file can't be attached, so a required one may be
  /// missing for now.
  List<String> _missingFiles() {
    final def = definition;
    if (def == null || !isOffline) return const [];
    return [
      for (final f in def.fields)
        if (!def.isGridSection(f.section) &&
            f.type == 'file' &&
            f.isRequired &&
            fields[f.name] != null &&
            isVisible(f) &&
            !FormRules.isFilled(fields[f.name]!.value.value))
          f.caption,
    ];
  }

  void _updateDraftState() {
    final waiting = _waitingFields();
    waitingNames.assignAll(waiting);
    canSaveDraft.value =
        (launch.mode == FormMode.create || launch.isDraft) &&
        (waiting.isNotEmpty || _missingFiles().isNotEmpty);
  }

  /// Keeps what is filled in as a draft, with no checks. It is sent from the
  /// Work Space once the missing values are there.
  Future<void> saveDraft() async {
    if (isSubmitting.value || !canSaveDraft.value) return;
    isSubmitting.value = true;
    banner.value = null;
    try {
      if (store.orgId != _org || store.userId != _user) {
        banner.value = 'You switched enterprise. This form was not saved.';
        return;
      }
      _calcTimer?.cancel();
      await _calc();
      final values = buildValues();
      final waiting = [..._waitingFields(), ..._missingFiles()];
      if (launch.mode == FormMode.create) {
        await submissions.submitForm(
          launch.name,
          values,
          cid: cid,
          scope: definition!.scope,
          caption: definition!.caption,
          chat: launch.convId,
          waiting: waiting,
        );
      } else {
        await submissions.resendFailed(
          launch.submissionId!,
          values,
          waiting: waiting,
        );
      }
      _isClosing = true;
      Get.back<bool>(result: true);
    } on Object {
      banner.value = "That couldn't be saved. Try again.";
    } finally {
      if (!_isClosing) isSubmitting.value = false;
    }
  }

  // ---- sending -------------------------------------------------------------------------

  /// Checks, writes the save and its outbox entry, and closes. A second tap
  /// while this runs does nothing, and the same id is used regardless.
  Future<void> done() async {
    if (isSubmitting.value || hasBlockingField.value) return;
    isSubmitting.value = true;
    banner.value = null;
    try {
      if (store.orgId != _org || store.userId != _user) {
        banner.value = 'You switched enterprise. This form was not sent.';
        return;
      }
      if (waitingNames.isNotEmpty) {
        banner.value =
            'Waiting for connection to fill ${waitingNames.join(', ')}.';
        return;
      }
      _calcTimer?.cancel();
      if (!await _calc()) {
        banner.value = "The calculations couldn't be worked out. Try again.";
        return;
      }
      if (!await validate()) {
        banner.value ??= 'Check the fields marked in red.';
        return;
      }
      final values = buildValues();
      final def = definition!;
      switch (launch.mode) {
        case FormMode.create:
          await submissions.submitForm(
            launch.name,
            values,
            cid: cid,
            scope: def.scope,
            caption: def.caption,
            chat: launch.convId,
          );
        case FormMode.edit:
          await submissions.editSubmission(
            launch.submissionId!,
            values,
            cid: cid,
          );
        case FormMode.resubmit:
          await submissions.resubmit(launch.submissionId!, values, cid: cid);
        case FormMode.resend:
          await submissions.resendFailed(launch.submissionId!, values);
      }
      _isClosing = true;
      Get.back<bool>(result: true);
    } on Object {
      banner.value = "That couldn't be saved. Try again.";
    } finally {
      if (!_isClosing) isSubmitting.value = false;
    }
  }

  /// The server's own refusal, put on the fields it names.
  void showServerErrors(Object? details) {
    final def = definition;
    if (def == null) return;
    final errors = FormRules.serverErrors(details);
    final rest = <String>[];
    GlobalKey? first;
    errors.forEach((key, message) {
      final parts = key.split('.');
      if (parts.length == 1 && fields.containsKey(key)) {
        fields[key]!.error.value = message;
        first ??= fields[key]!.key;
      } else if (parts.length == 1 && grids.containsKey(key)) {
        grids[key]!.error.value = message;
        first ??= grids[key]!.key;
      } else if (parts.length == 3 && grids.containsKey(parts.first)) {
        final grid = grids[parts.first]!;
        final index = int.tryParse(parts[1]) ?? -1;
        final cell = index >= 0 && index < grid.rows.length
            ? grid.rows[index].fields[parts[2]]
            : null;
        if (cell != null) {
          cell.error.value = message;
          first ??= cell.key;
        } else {
          rest.add(FormRules.describe(def, key, message));
        }
      } else {
        rest.add(FormRules.describe(def, key, message));
      }
    });
    banner.value = rest.isEmpty
        ? 'Some fields need attention.'
        : rest.join('\n');
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(first));
  }

  @override
  void onClose() {
    _isDisposed = true;
    _calcTimer?.cancel();
    _onlineWorker?.dispose();
    scroll.dispose();
    for (final f in fields.values) {
      f.dispose();
    }
    for (final g in grids.values) {
      g.dispose();
    }
    super.onClose();
  }
}
