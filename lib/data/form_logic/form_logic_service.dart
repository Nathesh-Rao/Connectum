import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:get/get.dart';
import 'package:quickjs_engine/quickjs_engine.dart';

import '../../core/debug/seed_ui.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'form_logic_assets.dart';

/// What a call to the logic gives back: a value, or the reason there is none.
/// Calls never throw.
class FormLogicResult<T> {
  const FormLogicResult.ok(T this.value) : error = null;
  const FormLogicResult.failed(String this.error) : value = null;

  final T? value;
  final String? error;

  bool get isOk => error == null;
}

/// The form logic (`ConnectumFormLogic`, JavaScript) in one QuickJS engine that
/// lives in a background isolate for as long as the app does. Plain JSON goes
/// in and out; the UI thread only waits on a port. A call that takes longer
/// than [timeout] ends with an error and the engine is started again.
///
/// One engine per signed-in person: when the organisation or the user behind
/// the session changes (sign out, switching organisation, `session_replaced`,
/// a new sign-in) the engine is stopped and the person's details dropped; the
/// next call starts a clean engine and loads the new person's details.
class FormLogicService extends GetxService {
  FormLogicService(this._store, this._socket);

  static const timeout = Duration(seconds: 4);

  final SessionStore _store;
  final SocketService _socket;

  /// Counts up when more of the person's details arrive after a form opened.
  final personVersion = 0.obs;
  String? _personKey;
  Map<String, dynamic>? _globals;
  Future<void>? _loadingPerson;
  Worker? _sessionWorker;

  Future<void>? _starting;
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _replies;
  final _waiting = <int, Completer<String>>{};
  int _seq = 0;
  String _dateFormat = 'dd/mm/yyyy';
  FormLogicAssets? _assets;

  @override
  void onInit() {
    super.onInit();
    _personKey = _currentKey;
    _sessionWorker = ever(_store.current, (_) {
      if (_currentKey == _personKey) return;
      _personKey = _currentKey;
      _globals = null;
      _loadingPerson = null;
      _stop('signed-in person changed');
    });
  }

  String? get _currentKey {
    final info = _store.current.value;
    return info == null ? null : '${info.orgId}/${info.userId}';
  }

  /// Loads the signed-in person's own details (`globals.list`, then the slower
  /// `globals.resolve`) and gives them to the logic as `login_<name>` (the
  /// logic also reads the plain and `global_` names). Does nothing without a
  /// connection; the form then reads those names as empty.
  Future<void> ensurePerson() {
    if (_globals != null || _currentKey == null) return Future.value();
    return _loadingPerson ??= _loadPerson(_currentKey!).whenComplete(() {
      if (_globals == null) _loadingPerson = null;
    });
  }

  Future<void> _loadPerson(String key) async {
    if (SeedUi.isActive || !_socket.isOnline) return;
    try {
      final listed = await _socket.sdCall('globals.list', {});
      final values = listed['values'];
      if (key != _personKey || values is! Map) return;
      await _setGlobals(key, values.cast<String, dynamic>());
    } on Object {
      return;
    }
    unawaited(_resolvePerson(key));
  }

  Future<void> _resolvePerson(String key) async {
    try {
      final resolved = await _socket.sdCall('globals.resolve', {});
      final values = resolved['values'];
      if (key != _personKey || values is! Map) return;
      await _setGlobals(key, {...?_globals, ...values.cast<String, dynamic>()});
      personVersion.value++;
    } on Object {
      return;
    }
  }

  Future<void> _setGlobals(String key, Map<String, dynamic> values) async {
    _globals = values;
    final r = await _call('setGlobals', [values]);
    if (!r.isOk && key == _personKey) _globals = null;
  }

  /// Whether a condition (`{field, op, value}`, `{all}`, `{any}`) holds for
  /// [values]: the web's `evalCondition`, not a copy of it.
  Future<FormLogicResult<bool>> evalCondition(
    Object? condition,
    Map<String, dynamic> values,
  ) async {
    final r = await _call('evalCondition', [condition, values]);
    return r.isOk
        ? FormLogicResult.ok(r.value == true)
        : FormLogicResult.failed(r.error!);
  }

  Future<FormLogicResult<bool>> isEmpty(Object? value) async {
    final r = await _call('isEmpty', [value]);
    return r.isOk
        ? FormLogicResult.ok(r.value == true)
        : FormLogicResult.failed(r.error!);
  }

  /// Many conditions in one call. Each item is `{k, c}` (key, condition) with
  /// an optional `r`, a grid row's cells, which are laid over [values] so the
  /// cell's own row is looked at first. Answers key -> met.
  Future<FormLogicResult<Map<String, bool>>> evalConditions(
    Map<String, dynamic> values,
    List<Map<String, dynamic>> items,
  ) async {
    final r = await _map('evalConditions', [values, items]);
    if (!r.isOk) return FormLogicResult.failed(r.error!);
    return FormLogicResult.ok({
      for (final e in r.value!.entries) e.key: e.value == true,
    });
  }

  Future<FormLogicResult<Map<String, dynamic>>> applyFormCalcs(
    List<Map<String, dynamic>> fields,
    List<Map<String, dynamic>> grids,
    Map<String, dynamic> values,
  ) => _map('applyFormCalcs', [fields, grids, values]);

  Future<FormLogicResult<String?>> fieldRuleError(
    Map<String, dynamic> field,
    Object? value,
    Map<String, dynamic> valuesWithBlanks,
  ) async {
    final r = await _call('fieldRuleError', [field, value, valuesWithBlanks]);
    if (!r.isOk) return FormLogicResult.failed(r.error!);
    final v = r.value;
    return FormLogicResult.ok(v?.toString());
  }

  Future<FormLogicResult<Object?>> evaluateExpression(
    String expr,
    Map<String, dynamic> values,
  ) => _call('evaluateExpression', [expr, values]);

  Future<FormLogicResult<Map<String, dynamic>>> withBlanks(
    List<String> ids,
    Map<String, dynamic> values,
  ) => _map('withBlanks', [ids, values]);

  Future<FormLogicResult<List<String>>> usedFields(
    String expr,
    List<String> ids,
  ) async {
    final r = await _call('usedFields', [expr, ids]);
    if (!r.isOk) return FormLogicResult.failed(r.error!);
    final v = r.value;
    return FormLogicResult.ok(v is List ? v.map((e) => '$e').toList() : []);
  }

  Future<FormLogicResult<bool>> hasCalc(Map<String, dynamic> field) =>
      _bool('hasCalc', field);

  Future<FormLogicResult<bool>> canCalc(Map<String, dynamic> field) =>
      _bool('canCalc', field);

  /// `dd/mm/yyyy` (the default) or `mm/dd/yyyy`. Kept and applied again if the
  /// engine has to be restarted.
  Future<FormLogicResult<void>> setDateFormat(String format) async {
    _dateFormat = format;
    final r = await _call('setDateFormat', [format]);
    return r.isOk
        ? const FormLogicResult.ok(null)
        : FormLogicResult.failed(r.error!);
  }

  Future<FormLogicResult<Map<String, dynamic>>> _map(
    String op,
    List<Object?> args,
  ) async {
    final r = await _call(op, args);
    if (!r.isOk) return FormLogicResult.failed(r.error!);
    final v = r.value;
    return v is Map
        ? FormLogicResult.ok(v.cast<String, dynamic>())
        : const FormLogicResult.failed('unexpected answer');
  }

  Future<FormLogicResult<bool>> _bool(String op, Object? arg) async {
    final r = await _call(op, [arg]);
    return r.isOk
        ? FormLogicResult.ok(r.value == true)
        : FormLogicResult.failed(r.error!);
  }

  Future<FormLogicResult<Object?>> _call(String op, List<Object?> args) async {
    try {
      final String payload;
      try {
        payload = jsonEncode(args);
      } on Object {
        return const FormLogicResult.failed('values are not plain JSON');
      }
      await _start();
      final port = _port;
      if (port == null) {
        return const FormLogicResult.failed('engine not running');
      }
      final id = ++_seq;
      final done = Completer<String>();
      _waiting[id] = done;
      port.send([id, op, payload]);
      final String raw;
      try {
        raw = await done.future.timeout(timeout);
      } on TimeoutException {
        _waiting.remove(id);
        _stop('timed out');
        return FormLogicResult.failed(
          '$op timed out after ${timeout.inSeconds} s',
        );
      }
      final reply = jsonDecode(raw) as Map<String, dynamic>;
      if (reply['e'] != null) return FormLogicResult.failed('${reply['e']}');
      return FormLogicResult.ok(reply['v']);
    } on Object catch (e) {
      return FormLogicResult.failed(e.toString());
    }
  }

  Future<void> _start() => _starting ??= _spawn().whenComplete(() {
    if (_port == null) _starting = null;
  });

  Future<void> _spawn() async {
    final assets = _assets ??= await FormLogicAssets.loadVerified();
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is String && !ready.isCompleted) {
        ready.completeError(m);
      } else if (m is List && m.length == 2) {
        _waiting.remove(m[0] as int)?.complete(m[1] as String);
      }
    });
    final isolate = await Isolate.spawn(_entry, [
      replies.sendPort,
      assets.shim,
      assets.bundle,
    ], onExit: replies.sendPort);
    try {
      _port = await ready.future.timeout(const Duration(seconds: 15));
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      replies.close();
      rethrow;
    }
    _isolate = isolate;
    _replies = replies;
    final globals = _globals;
    if (globals != null) {
      _port!.send([
        0,
        'setGlobals',
        jsonEncode([globals]),
      ]);
    }
    if (_dateFormat != 'dd/mm/yyyy') {
      _port!.send([
        0,
        'setDateFormat',
        jsonEncode([_dateFormat]),
      ]);
    }
  }

  void _stop(String why) {
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    _isolate = null;
    _replies = null;
    _port = null;
    _starting = null;
    final pending = _waiting.values.toList();
    _waiting.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.complete(jsonEncode({'e': 'engine stopped: $why'}));
    }
  }

  @override
  void onClose() {
    _sessionWorker?.dispose();
    _stop('closed');
    super.onClose();
  }

  static const _dispatch = r'''
var __call = function (op, argsJson) {
  var L = ConnectumFormLogic, a = JSON.parse(argsJson), r;
  var idOf = function (f) { return f.name; };
  switch (op) {
    case 'applyFormCalcs': r = L.applyFormCalcs(a[0], a[1], a[2], idOf); break;
    case 'fieldRuleError': r = L.fieldRuleError(a[0], a[1], a[2]); break;
    case 'evaluateExpression': r = L.evaluateExpression(a[0], a[1]); break;
    case 'withBlanks': r = L.withBlanks(a[0], a[1]); break;
    case 'usedFields': r = L.usedFields(a[0], a[1]); break;
    case 'hasCalc': r = L.hasCalc(a[0]); break;
    case 'canCalc': r = L.canCalc(a[0]); break;
    case 'setDateFormat': L.SetDateFormat(a[0]); r = null; break;
    case 'setGlobals': L.setRuleGlobals(a[0]); r = null; break;
    case 'evalCondition': r = L.evalCondition(a[0], a[1]); break;
    case 'isEmpty': r = L.isEmpty(a[0]); break;
    case 'evalConditions':
      r = {};
      a[1].forEach(function (it) {
        var v = a[0];
        if (it.r) { v = {}; for (var k in a[0]) v[k] = a[0][k]; for (var j in it.r) v[j] = it.r[j]; }
        r[it.k] = L.evalCondition(it.c, v);
      });
      break;
    default: throw new Error('unknown op ' + op);
  }
  return JSON.stringify({ v: r === undefined ? null : r });
};
''';

  static void _entry(List<Object?> boot) {
    final out = boot[0] as SendPort;
    final inbox = ReceivePort();
    QuickJsRuntime2? rt;
    String run(String code) {
      final r = rt!.evaluate(code);
      if (r.isError) throw StateError(r.stringResult);
      return r.stringResult;
    }

    try {
      rt = QuickJsRuntime2();
      run(boot[1] as String);
      run(boot[2] as String);
      run(_dispatch);
    } on Object catch (e) {
      out.send('engine failed to load: $e');
      return;
    }
    out.send(inbox.sendPort);
    inbox.listen((m) {
      final msg = m as List;
      String reply;
      try {
        final code = '__call(${jsonEncode(msg[1])}, ${jsonEncode(msg[2])})';
        reply = run(code);
      } on Object catch (e) {
        reply = jsonEncode({'e': e.toString()});
      }
      if (msg[0] != 0) out.send([msg[0], reply]);
    });
  }
}
