import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_state_view.dart';
import '../../data/models/form_definition.dart';
import '../../data/models/form_option.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import 'form_rules.dart';
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
  });

  static const maxRows = 200;

  final FormLaunch launch;
  final SubmissionRepository submissions;
  final FormOptionsRepository options;
  final SessionStore store;
  final ConnectivityService connectivity;

  final viewState = AppViewState.loading.obs;
  final isSubmitting = false.obs;
  final banner = RxnString();
  final hasBlockingField = false.obs;
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

  bool get isEncryptedChat => launch.convId != null && launch.isEncryptedChat;

  bool get isDirty => definition != null && _snapshot() != _initial;

  @override
  void onInit() {
    super.onInit();
    // A form that couldn't be opened offline tries again when the network
    // returns.
    _onlineWorker = ever(connectivity.state, (state) {
      if (state == AppConnectivity.online &&
          viewState.value == AppViewState.offline) {
        unawaited(_load());
      }
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
    _build(def);
    _initial = _snapshot();
    if (launch.errorDetails != null) showServerErrors(launch.errorDetails);
    unawaited(options.markUsed(launch.name, def.scope, def.caption));
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
      if (f.type == 'list') unawaited(loadChoices(input));
    }
    for (final s in def.sections) {
      if (!s.isGrid) continue;
      final columns = def.columnsOf(s.name);
      final grid = GridInput(s, columns);
      final savedRows = isEdit ? saved[s.name] : null;
      if (savedRows is List) {
        for (final row in savedRows) {
          if (row is Map) grid.rows.add(_row(columns, row, now, isSaved: true));
        }
      }
      if (grid.rows.isEmpty && !isEdit) {
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
    for (final input in row.fields.values) {
      if (input.def.type == 'list') unawaited(loadChoices(input));
    }
    return row;
  }

  // ---- what is shown --------------------------------------------------------------

  Object? _valueOf(String name, RowInput? row) {
    final inRow = row?.fields[name];
    if (inRow != null) return inRow.value.value;
    return fields[name]?.value.value;
  }

  /// A field is shown when its own condition and its section's both hold. A
  /// grid field's condition looks at its own row first. Reads the values it
  /// depends on, so an Obx around it rebuilds when they change.
  bool isVisible(FormFieldDef f, {RowInput? row}) {
    final def = definition;
    if (def == null || f.raw['hidden'] == true) return false;
    final section = def.sectionOf(f.section);
    if (section != null &&
        !FormRules.matches(section.condition, (n) => _valueOf(n, null))) {
      return false;
    }
    return FormRules.matches(f.condition, (n) => _valueOf(n, row));
  }

  /// True when showing this field depends on other answers (its own
  /// condition or its section's). Only those need to watch values.
  bool hasCondition(FormFieldDef f) =>
      f.condition != null ||
      definition?.sectionOf(f.section)?.condition != null;

  bool get hasSectionConditions =>
      definition?.sections.any((s) => s.condition != null) ?? false;

  bool isSectionVisible(FormSectionDef s) =>
      FormRules.matches(s.condition, (n) => _valueOf(n, null));

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

  void setValue(FieldInput f, Object? value) {
    f.value.value = value;
    if (f.error.value != null) f.error.value = null;
    if (banner.value != null && !hasBlockingField.value) banner.value = null;
  }

  RowInput? addRow(GridInput grid) {
    if (grid.rows.length >= maxRows) return null;
    final row = _row(grid.columns, const {}, DateTime.now(), isSaved: false);
    grid.rows.add(row);
    grid.error.value = null;
    return row;
  }

  void removeRow(GridInput grid, RowInput row) {
    grid.rows.remove(row);
    // The row's editors are still on screen until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  Future<void> loadChoices(FieldInput f) async {
    if (f.choices.value != null || f.isLoadingChoices.value) return;
    final source = f.def.source;
    if (source.isEmpty) {
      f.choices.value = [for (final o in f.def.options) FormChoice(o, o)];
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

  /// Marks every problem on screen and returns whether there were none.
  bool validate() {
    final def = definition;
    if (def == null) return false;
    var firstBad = false;
    void bad(GlobalKey key) {
      if (firstBad) return;
      firstBad = true;
      final ctx = key.currentContext;
      if (ctx != null) {
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.1,
            duration: const Duration(milliseconds: 250),
          ),
        );
      }
    }

    for (final f in def.fields) {
      if (def.isGridSection(f.section)) continue;
      final state = fields[f.name]!;
      if (!isVisible(f)) {
        state.error.value = null;
        continue;
      }
      final message = FormRules.check(f, state.value.value);
      state.error.value = message;
      if (message != null) bad(state.key);
    }
    for (final g in grids.values) {
      g.error.value = null;
      if (!isSectionVisible(g.section)) continue;
      for (final row in g.rows) {
        for (final c in g.columns) {
          final state = row.fields[c.name]!;
          if (!isVisible(c, row: row)) {
            state.error.value = null;
            continue;
          }
          final message = FormRules.check(c, state.value.value);
          state.error.value = message;
          if (message != null) bad(state.key);
        }
      }
    }
    return !firstBad;
  }

  /// Only what is shown and filled in; a grid sends every row in place (an
  /// empty row is `{}`), none at all when every row is empty.
  Map<String, dynamic> buildValues() {
    final def = definition!;
    final out = <String, dynamic>{};
    for (final f in def.fields) {
      if (def.isGridSection(f.section)) continue;
      if (!isVisible(f)) continue;
      final v = FormRules.toSent(f, fields[f.name]!.value.value);
      if (v != null) out[f.name] = v;
    }
    for (final g in grids.values) {
      if (!isSectionVisible(g.section)) continue;
      final rows = <Map<String, dynamic>>[];
      for (final row in g.rows) {
        final cells = <String, dynamic>{};
        for (final c in g.columns) {
          if (!isVisible(c, row: row)) continue;
          final v = FormRules.toSent(c, row.fields[c.name]!.value.value);
          if (v != null) cells[c.name] = v;
        }
        rows.add(cells);
      }
      if (rows.any((r) => r.isNotEmpty)) out[g.section.name] = rows;
    }
    return out;
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
      if (!validate()) {
        banner.value = 'Check the fields marked in red.';
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
    errors.forEach((key, message) {
      final parts = key.split('.');
      if (parts.length == 1 && fields.containsKey(key)) {
        fields[key]!.error.value = message;
      } else if (parts.length == 1 && grids.containsKey(key)) {
        grids[key]!.error.value = message;
      } else if (parts.length == 3 && grids.containsKey(parts.first)) {
        final grid = grids[parts.first]!;
        final index = int.tryParse(parts[1]) ?? -1;
        final cell = index >= 0 && index < grid.rows.length
            ? grid.rows[index].fields[parts[2]]
            : null;
        if (cell != null) {
          cell.error.value = message;
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
  }

  @override
  void onClose() {
    _isDisposed = true;
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
