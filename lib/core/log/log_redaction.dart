import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Turns an API request or response into a safe log string. Every list below
/// is meant to be edited: add a new secret-like key or a new sensitive action
/// here, nowhere else.
class LogRedaction {
  LogRedaction._();

  static const mask = '***';

  /// Message text is replaced by its length. Flip to log chat text.
  // ignore: constant_identifier_names
  static const bool MASK_MESSAGE_TEXT = true;

  /// Keys compared lower-case with `_` and `-` removed, at any depth.
  static const Set<String> secretKeys = {
    'password',
    'passwd',
    'pwd',
    'pin',
    'otp',
    'token',
    'accesstoken',
    'refreshtoken',
    'idtoken',
    'secret',
    'apikey',
    'authorization',
    'cookie',
    'setcookie',
    'session',
    'sid',
    'privatekey',
    'publickey',
    'key',
    'recovery',
    'recoverycode',
    'mnemonic',
    'signature',
    'jwt',
    'credential',
    'devicekey',
    'salt',
  };

  /// Key prefixes (same normal form) that are secret: `wrappedKey`, ...
  static const List<String> secretKeyPrefixes = ['wrapped'];

  /// `code` is secret on its own and inside any key naming an otp or a
  /// verification.
  static const List<String> secretKeyParts = ['otp', 'verification'];

  static const Set<String> textKeys = {
    'text',
    'message',
    'body',
    'content',
    'caption',
    'comment',
  };

  static const Set<String> fileNameKeys = {
    'filename',
    'attachmentname',
    'originalname',
  };

  /// Only these actions have their text keys masked (chat and message
  /// actions: sending, editing, threads, comments). Actions starting with `#`
  /// are typed chat commands. Form captions, labels and names elsewhere are
  /// logged as they are.
  static const Set<String> chatActions = {
    'conv.send',
    'conv.edit',
    'message.send',
    'message.edit',
    'record.send',
    'record.thread',
    'care.thread',
    'task.send',
    'req.respond',
    'assistant.relay',
    'msg.pins',
    'msg.saved',
  };

  /// Socket actions whose whole request and response are hidden.
  static const Set<String> sensitiveActions = {
    'session.current',
    'connect.claim',
    'connect_claim',
    'connect.my',
  };

  /// Socket action prefixes (E2E keys, recovery, device keys) and REST path
  /// prefixes (sign-in, OTP, passwords, device approval, registration).
  static const List<String> sensitivePrefixes = [
    'e2e.',
    '/login',
    '/password',
    '/register',
    '/setup',
    '/enter',
    '/authentication',
    '/session',
    '/device',
    '/e2e',
  ];

  static const Set<String> headerAllowlist = {
    'content-type',
    'content-length',
    'status',
    'x-request-id',
  };

  static const int maxItems = 20;
  static const int shownItems = 3;
  static const int maxString = 200;
  static const int maxBody = 2048;
  static const int maxFailedBody = 8192;
  static const int _maxDepth = 12;

  static const redactedAction = '<redacted: auth/crypto action>';
  static const errorText = '<body not logged: redaction error>';

  @visibleForTesting
  static int calls = 0;

  /// `POST /login/verify` and `e2e.register` alike.
  static bool isSensitiveAction(String action) {
    final a = action.contains(' ') ? action.split(' ').last : action;
    if (sensitiveActions.contains(a)) return true;
    for (final p in sensitivePrefixes) {
      if (a.startsWith(p)) return true;
    }
    return false;
  }

  static bool isChatAction(String action) {
    final a = action.contains(' ') ? action.split(' ').last : action;
    return a.startsWith('#') || chatActions.contains(a);
  }

  static bool isSecretKey(String key) {
    final k = key.toLowerCase().replaceAll(RegExp(r'[_\-]'), '');
    if (secretKeys.contains(k)) return true;
    if (k == 'code') return true;
    for (final p in secretKeyPrefixes) {
      if (k.startsWith(p)) return true;
    }
    for (final p in secretKeyParts) {
      if (k.contains(p)) return true;
    }
    return false;
  }

  /// The loggable text of [data] for [action]; never throws, never returns
  /// the raw body when redaction fails.
  static String body(String action, Object? data, {bool isFailure = false}) {
    calls++;
    try {
      if (isSensitiveAction(action)) return redactedAction;
      final cap = isFailure ? maxFailedBody : maxBody;
      final isMasked = MASK_MESSAGE_TEXT && isChatAction(action);
      if (data is String && isMasked && !_looksJson(data)) {
        return '<text ${data.length} chars>';
      }
      return _cap(_encode(_clean(data, 0, isMasked)), cap);
    } catch (_) {
      return errorText;
    }
  }

  /// Only allowlisted headers; values are kept as sent.
  static Map<String, String> headers(Map<String, Object?> all) {
    try {
      return {
        for (final e in all.entries)
          if (headerAllowlist.contains(e.key.toLowerCase()))
            e.key: '${e.value}',
      };
    } catch (_) {
      return const {};
    }
  }

  static bool _looksJson(String s) {
    final t = s.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  static String _encode(Object? v) => v is String ? v : jsonEncode(v);

  static String _cap(String s, int cap) => s.length <= cap
      ? s
      : '${s.substring(0, cap)}...(+${s.length - cap} chars)';

  static Object? _clean(Object? v, int depth, bool isMasked) {
    if (depth > _maxDepth) return '<too deep>';
    if (v == null || v is num || v is bool) return v;
    if (v is Uint8List) return _file(v.length);
    if (v is List<int> && v.length > 64) return _file(v.length);
    if (v is Map) {
      return {
        for (final e in v.entries)
          '${e.key}': _value('${e.key}', e.value, depth + 1, isMasked),
      };
    }
    if (v is Iterable) {
      final list = v.toList();
      final shown = list.length > maxItems ? list.take(shownItems) : list;
      return [
        for (final i in shown) _clean(i, depth + 1, isMasked),
        if (list.length > maxItems) '(+${list.length - shownItems} more items)',
      ];
    }
    if (v is String) return _string(v, depth, isMasked);
    final name = v.runtimeType.toString();
    if (name == 'FormData') return _file(_lengthOf(v));
    return '<$name>';
  }

  static int _lengthOf(Object form) {
    try {
      return (form as dynamic).length as int;
    } catch (_) {
      return 0;
    }
  }

  static String _file(int bytes) => '<file upload $bytes bytes, name masked>';

  static Object? _value(String key, Object? value, int depth, bool isMasked) {
    if (isSecretKey(key)) return mask;
    final k = key.toLowerCase().replaceAll(RegExp(r'[_\-]'), '');
    if (fileNameKeys.contains(k)) return '<name masked>';
    if (isMasked && textKeys.contains(k) && value is String) {
      return '<text ${value.length} chars>';
    }
    return _clean(value, depth, isMasked);
  }

  static Object? _string(String s, int depth, bool isMasked) {
    final t = s.trimLeft();
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        return _clean(jsonDecode(s), depth + 1, isMasked);
      } on FormatException {
        // Plain text that only looks like JSON.
      }
    }
    return s.length > maxString ? '<${s.length} chars>' : s;
  }
}
