import 'dart:convert';

/// Who is signed in, for the log header and `CONTEXT` lines. Never a token.
class LogContext {
  const LogContext({this.user, this.org, this.isKnown = false});

  static const unknown = LogContext();

  /// `Name <email>`, or null when signed out.
  final String? user;
  final String? org;

  /// False until the session has been read; then the labels say "unknown".
  final bool isKnown;

  String get userLabel => isKnown ? (user ?? 'not signed in') : 'unknown';
  String get orgLabel => isKnown ? (org ?? 'unknown') : 'unknown';

  @override
  bool operator ==(Object other) =>
      other is LogContext &&
      other.user == user &&
      other.org == org &&
      other.isKnown == isKnown;

  @override
  int get hashCode => Object.hash(user, org, isKnown);
}

/// Static facts about this install, read once.
class LogEnvironment {
  const LogEnvironment({this.version = 'unknown', this.device = 'unknown'});

  final String version;
  final String device;
}

/// Pure text building for the log file: no I/O, no clock of its own.
class LogFormatter {
  LogFormatter._();

  static const appName = 'Connectum Mobile';
  static final separator = '=' * 80;
  static const capLine =
      'LOG SIZE LIMIT REACHED (10 MB): further entries are not written until a new file is started';

  static String two(int v) => v.toString().padLeft(2, '0');

  static String date(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${two(t.month)}-${two(t.day)}';

  static String time(DateTime t) =>
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

  /// 2026-11-23 17:34:12.345
  static String timestamp(DateTime t) =>
      '${date(t)} ${time(t)}.${t.millisecond.toString().padLeft(3, '0')}';

  /// 2026-11-23 17:34:12 +05:30
  static String withOffset(DateTime t) {
    final o = t.timeZoneOffset;
    final minutes = o.inMinutes.abs();
    final sign = o.isNegative ? '-' : '+';
    return '${date(t)} ${time(t)} $sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  /// ConnectumMobileLog_20261123_173412.txt
  static String fileName(DateTime t) =>
      'ConnectumMobileLog_${t.year.toString().padLeft(4, '0')}${two(t.month)}'
      '${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}.txt';

  static final _frame = RegExp(r'#\d+\s+(.+?)\s+\((.+?):(\d+)(?::\d+)?\)');

  /// "Class.method (file.dart:123)" of the first app frame, or null.
  static String? caller(StackTrace stack) {
    for (final line in stack.toString().split('\n')) {
      final m = _frame.firstMatch(line);
      if (m == null) continue;
      final path = m.group(2)!;
      if (!path.startsWith('package:connectum/')) continue;
      if (path.contains('/core/log/')) continue;
      final file = path.substring(path.lastIndexOf('/') + 1);
      return '${m.group(1)} ($file:${m.group(3)})';
    }
    return null;
  }

  /// "Class.method (file.dart:123)" of the first app frame outside the log
  /// package and the files in [skip] (the API layer itself), or null.
  static String? apiCaller(StackTrace stack, List<String> skip) {
    for (final line in stack.toString().split('\n')) {
      final m = _frame.firstMatch(line);
      if (m == null) continue;
      final path = m.group(2)!;
      if (!path.startsWith('package:connectum/')) continue;
      if (path.contains('/core/log/')) continue;
      if (skip.any(path.endsWith)) continue;
      final file = path.substring(path.lastIndexOf('/') + 1);
      return '${m.group(1)} ($file:${m.group(3)})';
    }
    return null;
  }

  /// The first [max] frames, trimmed.
  static List<String> frames(StackTrace stack, {int max = 8}) => [
    for (final l in stack.toString().split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ].take(max).toList();

  static const width = 80;
  static const messageColumn = 27;
  static const messageWidth = width - messageColumn;
  static final detailIndent = ' ' * messageColumn;
  static const legend =
      'Legend: I info | W warning | E error | -> request | <- response | (xN) repeated N times';

  /// 10:10:06.785
  static String clock(DateTime t) =>
      '${time(t)}.${t.millisecond.toString().padLeft(3, '0')}';

  /// "-- 2026-11-24 ----...----" to 80 columns.
  static String dateLine(DateTime t) =>
      '${'-- ${date(t)} '.padRight(width, '-')}\n';

  static const _categories = {
    'app': 'APP',
    'lifecycle': 'APP',
    'app_settings': 'APP',
    'initial_binding': 'APP',
    'splash_controller': 'APP',
    'logs': 'APP',
    'logs_controller': 'APP',
    'session': 'SESSION',
    'session_store': 'SESSION',
    'session_repository': 'SESSION',
    'auth_repository': 'SESSION',
    'password_controller': 'SESSION',
    'enterprises_controller': 'SESSION',
    'context': 'SESSION',
    'socket': 'SOCKET',
    'socket_service': 'SOCKET',
    'connectivity': 'CONN',
    'connectivity_service': 'CONN',
    'push': 'PUSH',
    'push_payload': 'PUSH',
    'notifications': 'PUSH',
    'local_notification_service': 'PUSH',
    'feed_repository': 'PUSH',
    'app_database': 'DB',
    'sv_prefs': 'DB',
    'conversation_repository': 'SYNC',
    'message_repository': 'SYNC',
    'group_repository': 'SYNC',
    'command_repository': 'SYNC',
    'outbox': 'OUTBOX',
    'submission_repository': 'FORM',
    'form_options_repository': 'FORM',
    'form_file_repository': 'FORM',
    'struct_records_repository': 'FORM',
    'ticket_repository': 'FORM',
    'record_actions_queue': 'FORM',
    'deep_link_service': 'NAV',
    'link_launcher': 'NAV',
    'permission': 'PERM',
    'sd_call': 'API',
    'flutter_error': 'ERROR',
    'platform_error': 'ERROR',
  };

  /// The fixed-width category for a tag passed to AppLog. `API #<id>` tags
  /// are kept as they are.
  static String category(String tag) {
    if (tag.startsWith('API #')) return tag;
    final t = tag.toLowerCase();
    final known = _categories[t];
    if (known != null) return known;
    if (t.startsWith('e2e') || t.startsWith('hand_on')) return 'E2E';
    if (t.startsWith('encryption')) return 'E2E';
    final up = tag.toUpperCase();
    return up.length > 8 ? up.substring(0, 8) : up;
  }

  /// Greedy word wrap to [maxWidth]. A token longer than the width stays
  /// whole. With [onCommas] the breaks fall after commas and nothing is
  /// added between pieces.
  static List<String> wrap(String text, int maxWidth, {bool onCommas = false}) {
    final tokens = onCommas ? text.split(RegExp(r'(?<=,)')) : text.split(' ');
    final joiner = onCommas ? '' : ' ';
    final lines = <String>[];
    var cur = '';
    var hasCur = false;
    for (final t in tokens) {
      if (!hasCur) {
        if (t.isEmpty && lines.isNotEmpty) continue;
        cur = t;
        hasCur = true;
      } else if (cur.length + joiner.length + t.length > maxWidth &&
          t.isNotEmpty) {
        lines.add(cur);
        cur = t;
      } else {
        cur = '$cur$joiner$t';
      }
    }
    lines.add(cur);
    return lines;
  }

  /// One entry: a scan line (wrapped under the message column), then detail
  /// lines aligned under the message. The caller is its own detail line.
  /// [repeat] of 2 or more adds the `(xN)` suffix.
  static String entry({
    required DateTime at,
    required String level,
    required String tag,
    required String message,
    String? caller,
    List<String> details = const [],
    int repeat = 1,
  }) {
    final cleaned = message.replaceAll('\r\n', '\n').split('\n');
    final first = repeat >= 2 ? '${cleaned.first}  (x$repeat)' : cleaned.first;
    final lead = '${clock(at)}  $level  ${category(tag).padRight(8)}  ';
    final lines = wrap(first, messageWidth);
    final b = StringBuffer('$lead${lines.first}');
    for (final l in lines.skip(1)) {
      b.write('\n$detailIndent$l');
    }
    final rest = [
      if (caller != null) 'at $caller',
      ...cleaned.skip(1),
      ...details,
    ];
    for (final d in rest) {
      b.write('\n$detailIndent$d');
    }
    b.write('\n');
    return b.toString();
  }

  static String sessionBlock(DateTime at, String version) =>
      '$separator\n'
      'SESSION START   ${timestamp(at)}    app $version\n'
      '$separator\n'
      '${dateLine(at)}';

  static String contextLine(DateTime at, LogContext c) => entry(
    at: at,
    level: 'I',
    tag: 'session',
    message: 'user=${c.userLabel}  org=${c.orgLabel}',
  );

  static const _moreRe = r'^\(\+(\d+) more items\)$';

  /// The lines (unindented) of a redacted body: pretty JSON when the compact
  /// form is over 70 characters and the pretty form fits 40 lines, else
  /// compact JSON wrapped on commas. Never throws.
  static List<String> bodyLines(String body) {
    try {
      final t = body.trimLeft();
      if (t.startsWith('{') || t.startsWith('[')) {
        Object? parsed;
        var isJson = true;
        try {
          parsed = jsonDecode(body);
        } on FormatException {
          isJson = false;
        }
        if (isJson) {
          final compact = _compact(parsed);
          if (compact.length > 70) {
            final out = <String>[];
            _pretty(parsed, '', '', '', out);
            if (out.length <= 40) return out;
          }
          return wrap(compact, messageWidth, onCommas: true);
        }
        return wrap(body, messageWidth, onCommas: true);
      }
      return wrap(body, messageWidth);
    } catch (_) {
      return [body];
    }
  }

  static (List<Object?>, int) _shown(List<Object?> l) {
    var items = l;
    var extra = 0;
    if (items.isNotEmpty) {
      final last = items.last;
      final m = last is String ? RegExp(_moreRe).firstMatch(last) : null;
      if (m != null) {
        extra = int.tryParse(m.group(1) ?? '') ?? 0;
        items = items.sublist(0, items.length - 1);
      }
    }
    if (items.length > 3) {
      extra += items.length - 3;
      items = items.sublist(0, 3);
    }
    return (items, extra);
  }

  static String _compact(Object? v) {
    if (v is Map && v.isNotEmpty) {
      return '{${v.entries.map((e) => '${jsonEncode('${e.key}')}:${_compact(e.value)}').join(',')}}';
    }
    if (v is List && v.isNotEmpty) {
      final (items, extra) = _shown(v);
      final parts = [
        for (final i in items) _compact(i),
        if (extra > 0) '... (+$extra more items)',
      ];
      return '[${parts.join(',')}]';
    }
    return jsonEncode(v);
  }

  static void _pretty(
    Object? v,
    String pad,
    String lead,
    String trail,
    List<String> out,
  ) {
    if (v is Map && v.isNotEmpty) {
      out.add('$pad$lead{');
      final keys = v.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        _pretty(
          v[keys[i]],
          '$pad  ',
          '${jsonEncode('${keys[i]}')}: ',
          i < keys.length - 1 ? ',' : '',
          out,
        );
      }
      out.add('$pad}$trail');
    } else if (v is List && v.isNotEmpty) {
      final (items, extra) = _shown(v);
      out.add('$pad$lead[');
      for (var i = 0; i < items.length; i++) {
        _pretty(
          items[i],
          '$pad  ',
          '',
          i < items.length - 1 || extra > 0 ? ',' : '',
          out,
        );
      }
      if (extra > 0) out.add('$pad  ... (+$extra more items)');
      out.add('$pad]$trail');
    } else {
      out.add('$pad$lead${jsonEncode(v)}$trail');
    }
  }

  static String header({
    required LogEnvironment env,
    required String fileCreated,
    required DateTime started,
    required LogContext context,
    required bool isAppend,
  }) {
    String row(String label, String value) =>
        '${'$label:'.padRight(14)}$value\n';
    return '${row('App name', appName)}'
        '${row('App version', env.version)}'
        '${row('File created', fileCreated)}'
        '${row('Log started', '${withOffset(started)}${isAppend ? ' (new session added to this file)' : ''}')}'
        '${row('User', context.userLabel)}'
        '${row('Organisation', context.orgLabel)}'
        '${row('Device', env.device)}'
        '${row('API bodies', 'logged, secrets masked')}'
        '$separator\n'
        '$legend\n';
  }
}
