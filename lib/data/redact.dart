import 'dart:convert';

class Redact {
  Redact._();

  static const _hidden = {
    'token',
    'otp',
    'password',
    'trust',
    'proof',
    'ecdh',
    'sign',
  };

  static dynamic value(dynamic v, [String? key]) {
    if (key != null && _hidden.contains(key.toLowerCase())) return '<redacted>';
    if (v is Map) {
      return {
        for (final e in v.entries)
          e.key.toString(): value(e.value, e.key.toString()),
      };
    }
    if (v is List) return v.take(5).map(value).toList();
    if (key == 'text' && v is String) return '<text ${v.length}ch>';
    if (v is String && v.length > 40) return '${v.substring(0, 40)}...';
    return v;
  }

  static String event(Map<String, dynamic> e) => jsonEncode(value(e));

  static String shape(dynamic v) {
    if (v is Map) {
      return '{${v.entries.map((e) => '${e.key}:${shape(e.value)}').join(',')}}';
    }
    if (v is List) return v.isEmpty ? '[]' : '[${shape(v.first)}]';
    return v == null ? 'null' : v.runtimeType.toString();
  }
}
