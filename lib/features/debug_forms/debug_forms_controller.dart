import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/db/app_database.dart';
import '../../data/form_logic/form_logic_service.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/models/form_option.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import 'cache_vectors.dart';
import 'condition_vectors.dart';
import 'scope_vectors.dart';

/// Read-only look at the `sample_*` forms: the definition as the server sent
/// it, plain typed values, and what the form logic works out from them live.
class DebugFormsController extends GetxController {
  DebugFormsController({
    required this.session,
    required this.socket,
    required this.logic,
    required this.samples,
    required this.options,
    required this.db,
    required this.conversations,
    required this.messages,
  });

  final SessionStore session;
  final SocketService socket;
  final FormLogicService logic;
  final SampleForms samples;
  final FormOptionsRepository options;
  final AppDatabase db;
  final ConversationRepository conversations;
  final MessageRepository messages;

  /// The kept-lists checks; run on demand because they use the database.
  final cacheResults = <CacheVector>[].obs;

  final forms = <FormOption>[].obs;
  final isLoading = false.obs;
  final error = RxnString();
  final shape = Rxn<FormShape>();
  final openName = RxnString();

  /// Typed text per field (`name`) or grid cell (`section.row.name`).
  final typed = <String, String>{}.obs;
  final rowCounts = <String, int>{}.obs;

  /// What the logic answered for the current values.
  final calculated = <String, dynamic>{}.obs;
  final ruleMessages = <String, String>{}.obs;
  final visible = <String, bool>{}.obs;
  final logicError = RxnString();

  final results = <SampleFormResult>[].obs;
  final isChecking = false.obs;

  final _inputs = <String, TextEditingController>{};
  Timer? _debounce;
  int _generation = 0;

  bool get isReady => session.hasEnterpriseSession && socket.isOnline;

  @override
  void onReady() {
    super.onReady();
    unawaited(checkConditions());
    if (isReady) load();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.onClose();
  }

  final cleanupResult = RxnString();

  /// Deletes the cached rows and outbox of the active organisation and person
  /// only, then reads again and syncs from the server when online.
  Future<void> clearActiveOrg() async {
    final org = session.orgId;
    final user = session.userId;
    if (org == null || user == null) {
      cleanupResult.value = 'Not signed in to an organisation.';
      return;
    }
    await db.clearScopeRows(org, user);
    await conversations.reload();
    cleanupResult.value = 'Cleared the cached data of $org.';
    if (socket.isOnline) unawaited(messages.syncNow());
  }

  Future<void> runCacheVectors() async {
    cacheResults.assignAll(await CacheVectors.run(options));
    cacheResults.addAll(await ScopeVectors.run(db, conversations, messages));
  }

  TextEditingController inputFor(String key) =>
      _inputs.putIfAbsent(key, () => TextEditingController(text: typed[key]));

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      forms.assignAll(await samples.list());
    } on Object catch (e) {
      error.value = e.toString();
    }
    isLoading.value = false;
  }

  Future<void> open(FormOption o) async {
    isLoading.value = true;
    error.value = null;
    try {
      final s = FormShape(await samples.definition(o));
      for (final c in _inputs.values) {
        c.dispose();
      }
      _inputs.clear();
      typed.clear();
      rowCounts.clear();
      calculated.clear();
      ruleMessages.clear();
      visible.clear();
      for (final g in s.gridNames) {
        rowCounts[g] = 1;
      }
      shape.value = s;
      openName.value = o.target;
      await _recompute();
    } on SocketCallError catch (e) {
      error.value = '${e.code} ${e.message}'.trim();
    } on Object catch (e) {
      error.value = e.toString();
    }
    isLoading.value = false;
  }

  void close() {
    shape.value = null;
    openName.value = null;
  }

  void setValue(String key, String text) {
    typed[key] = text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _recompute);
  }

  void addRow(String section) {
    rowCounts[section] = (rowCounts[section] ?? 0) + 1;
    unawaited(_recompute());
  }

  void removeRow(String section) {
    final n = rowCounts[section] ?? 0;
    if (n == 0) return;
    for (final f in shape.value!.grids[section] ?? const []) {
      final k = '$section.${n - 1}.${f['name']}';
      typed.remove(k);
      _inputs.remove(k)?.dispose();
    }
    rowCounts[section] = n - 1;
    unawaited(_recompute());
  }

  Map<String, dynamic> _typedValues(FormShape s) {
    final values = <String, dynamic>{};
    for (final f in s.fields) {
      final t = typed[idText(f['name'])];
      if (t != null && t.isNotEmpty) values[idText(f['name'])] = t;
    }
    for (final g in s.gridNames) {
      values[g] = [
        for (var i = 0; i < (rowCounts[g] ?? 0); i++)
          {
            for (final f in s.grids[g] ?? const [])
              if ((typed['$g.$i.${f['name']}'] ?? '').isNotEmpty)
                idText(f['name']): typed['$g.$i.${f['name']}'],
          },
      ];
    }
    return values;
  }

  Future<void> _recompute() async {
    final s = shape.value;
    if (s == null) return;
    final run = ++_generation;
    final values = s.toLogic(_typedValues(s));
    final r = await logic.applyFormCalcs(s.fields, s.gridList, values);
    if (run != _generation) return;
    if (!r.isOk) {
      logicError.value = r.error;
      return;
    }
    logicError.value = null;
    final done = r.value!;
    final messages = <String, String>{};
    for (final f in s.fields) {
      final name = idText(f['name']);
      final m = await _rule(s, f, done[name], done);
      if (run != _generation) return;
      if (m != null) messages[name] = m;
    }
    for (final g in s.gridNames) {
      final rows = done[g] as List? ?? const [];
      final outer = {
        for (final e in done.entries)
          if (!s.gridNames.contains(e.key)) e.key: e.value,
      };
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i] is Map
            ? (rows[i] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        for (final f in s.grids[g] ?? const <Map<String, dynamic>>[]) {
          final name = idText(f['name']);
          final m = await _rule(s, f, row[name], {...outer, ...row});
          if (run != _generation) return;
          if (m != null) messages['$g.$i.$name'] = m;
        }
      }
    }
    calculated.assignAll(done);
    ruleMessages.assignAll(messages);
    final shown = await _visibility(s, done);
    if (run != _generation) return;
    visible.assignAll(shown);
  }

  Future<String?> _rule(
    FormShape s,
    Map<String, dynamic> field,
    Object? value,
    Map<String, dynamic> context,
  ) async {
    final rule = field['rule'];
    if (rule is! Map) return null;
    final blanks = await logic.withBlanks([
      for (final f in s.all) idText(f['name']),
    ], context);
    if (!blanks.isOk) return 'engine: ${blanks.error}';
    final r = await logic.fieldRuleError(field, value, blanks.value!);
    return r.isOk ? r.value : 'engine: ${r.error}';
  }

  Future<Map<String, bool>> _visibility(
    FormShape s,
    Map<String, dynamic> values,
  ) async {
    final sections = [
      for (final x in s.tstruct['sections'] as List? ?? const [])
        if (x is Map) x,
    ];
    Map? sectionOf(Object? name) =>
        sections.where((x) => x['name'] == name).firstOrNull;
    final items = <Map<String, dynamic>>[];
    for (final f in s.fields) {
      final name = idText(f['name']);
      if (f['condition'] != null) {
        items.add({'k': name, 'c': f['condition']});
      }
      final sc = sectionOf(f['section'])?['condition'];
      if (sc != null) items.add({'k': '$name\u00a7', 'c': sc});
    }
    final r = items.isEmpty
        ? const FormLogicResult<Map<String, bool>>.ok({})
        : await logic.evalConditions(values, items);
    final met = r.value ?? const <String, bool>{};
    return {
      for (final f in s.fields)
        idText(f['name']):
            f['hidden'] != true &&
            (met[idText(f['name'])] ?? true) &&
            (met['${idText(f['name'])}\u00a7'] ?? true),
    };
  }

  /// Each condition vector through the JS `evalCondition`: the answer it gave
  /// (null when the engine could not answer).
  final conditionResults = <bool?>[].obs;

  Future<void> checkConditions() async {
    final out = <bool?>[];
    for (final v in conditionVectors) {
      final r = await logic.evalCondition(v.condition, v.values);
      out.add(r.isOk ? r.value : null);
    }
    conditionResults.assignAll(out);
  }

  Future<void> checkAll() async {
    isChecking.value = true;
    results.clear();
    try {
      if (forms.isEmpty) await load();
      for (final o in forms) {
        results.add(await samples.check(o));
      }
    } on Object catch (e) {
      error.value = e.toString();
    }
    isChecking.value = false;
  }

  String describe(Map<String, dynamic> f) {
    final parts = <String>[
      idText(f['type']),
      if (f['required'] == true) 'required',
      if (f['hidden'] == true) 'hidden',
      if (f['readOnly'] == true) 'readOnly',
      if (f['multi'] == true) 'multi',
      if (f['rule'] != null) 'rule ${jsonEncode(f['rule'])}',
      if (f['calc'] != null) 'calc ${jsonEncode(f['calc'])}',
      if (f['condition'] != null) 'condition ${jsonEncode(f['condition'])}',
    ];
    return parts.join(' · ');
  }
}
