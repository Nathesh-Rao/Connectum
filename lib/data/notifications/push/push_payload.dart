import 'dart:convert';

import '../../models/ids.dart';

/// The small, text-free hint a push or a local notification carries:
/// enough to route the tap, never the message. Values arrive as strings from
/// a push provider, so every field is read tolerantly.
class PushPayload {
  const PushPayload({
    this.itemId,
    this.actionType,
    this.chatId,
    this.messageId,
    this.count = 1,
  });

  final String? itemId;
  final String? actionType;
  final String? chatId;
  final String? messageId;
  final int count;

  /// Null when [raw] holds nothing to route by.
  static PushPayload? tryParse(Object? raw) {
    Object? json = raw;
    if (json is String) {
      if (json.isEmpty) return null;
      try {
        json = jsonDecode(json);
      } catch (_) {
        return null;
      }
    }
    if (json is! Map) return null;
    final ref = json['ref'];
    final messageId =
        json['messageId'] ?? (ref is Map ? ref['messageId'] : null);
    final payload = PushPayload(
      itemId: _text(json['itemId']),
      actionType: _text(json['actionType']),
      chatId: _text(json['chatId']),
      messageId: _text(messageId),
      count: json['count'] == null ? 1 : intOf(json['count']).clamp(1, 1 << 30),
    );
    final isEmpty =
        payload.itemId == null &&
        payload.actionType == null &&
        payload.chatId == null &&
        payload.messageId == null;
    return isEmpty ? null : payload;
  }

  String toJson() => jsonEncode({
    if (itemId != null) 'itemId': itemId,
    if (actionType != null) 'actionType': actionType,
    if (chatId != null) 'chatId': chatId,
    if (messageId != null) 'messageId': messageId,
    if (count > 1) 'count': count,
  });

  static String? _text(Object? v) {
    final t = v == null ? '' : '$v';
    return t.isEmpty ? null : t;
  }
}
