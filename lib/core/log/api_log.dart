import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'log_formatter.dart';
import 'log_redaction.dart';

/// The one place API calls are written to the log file: two lines per call
/// (`->` request, `<-` answer) sharing a counter id. Bodies go through
/// [LogRedaction] first. Nothing is built while logging is off.
class ApiLog {
  ApiLog._();

  static int _seq = 0;

  static bool Function() isOn = () => AppLog.isFileOn;

  static void Function(String level, String tag, String message) write =
      AppLog.api;

  static const _apiLayer = [
    'socket_service.dart',
    'api_client.dart',
    'api_log.dart',
    'api_log_interceptor.dart',
  ];

  /// Writes the request entry and returns the call to finish, or null when
  /// logging is off.
  static ApiCall? begin(String action, Object? request, {StackTrace? stack}) {
    if (!isOn()) return null;
    try {
      final id = ++_seq;
      final caller = LogFormatter.apiCaller(
        stack ?? StackTrace.current,
        _apiLayer,
      );
      final call = ApiCall._(id, action, caller);
      write(
        'I',
        'API #$id',
        _join('$action  ->  request', null, LogRedaction.body(action, request)),
      );
      return call;
    } catch (e) {
      debugPrint('api log failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Status line, then the caller and body lines: the sink puts every line
  /// after the first under the message column.
  static String _join(
    String status,
    String? caller,
    String? body, {
    String? note,
  }) {
    final lines = [
      status,
      if (note != null) ...LogFormatter.wrap(note, LogFormatter.messageWidth),
      if (caller != null) 'at $caller',
      if (body != null && body.isNotEmpty && body != 'null')
        ...LogFormatter.bodyLines(body),
    ];
    return lines.join('\n');
  }
}

class ApiCall {
  ApiCall._(this.id, this.action, this.caller);

  final int id;
  final String action;
  final String? caller;
  final Stopwatch _watch = Stopwatch()..start();

  String get _tag => 'API #$id';
  int get _ms => _watch.elapsedMilliseconds;

  void ok(Object? data, {Map<String, Object?> headers = const {}}) {
    final count = _itemCount(data);
    _end(
      'I',
      ApiLog._join(
        '$action  <-  OK  $_ms ms${count > 0 ? '  ($count items)' : ''}${_headers(headers)}',
        caller,
        LogRedaction.body(action, data),
      ),
    );
  }

  /// The server answered with an error.
  void failed(String code, String message, {Object? body}) {
    final isHidden = LogRedaction.isSensitiveAction(action);
    _end(
      'E',
      ApiLog._join(
        '$action  <-  FAILED  $_ms ms  code=$code',
        caller,
        LogRedaction.body(action, body, isFailure: true),
        note: isHidden || message.isEmpty ? null : message,
      ),
    );
  }

  /// No answer at all: offline, dropped, timed out.
  void noResponse(String type, [String? detail]) => _end(
    'W',
    ApiLog._join(
      '$action  <-  NO RESPONSE  $_ms ms  $type${detail == null || detail.isEmpty ? '' : ' $detail'}',
      caller,
      null,
    ),
  );

  static int _itemCount(Object? data) {
    if (data is List) return data.length;
    final inner = data is Map ? data['data'] : null;
    if (inner is List) return inner.length;
    return 0;
  }

  String _headers(Map<String, Object?> h) {
    if (h.isEmpty || action.endsWith('/version')) return '';
    final kept = LogRedaction.headers(h);
    return kept.isEmpty
        ? ''
        : '  ${kept.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
  }

  void _end(String level, String message) {
    try {
      ApiLog.write(level, _tag, message);
    } catch (e) {
      debugPrint('api log failed: ${e.runtimeType}');
    }
  }
}
