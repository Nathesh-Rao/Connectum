import 'dart:convert';

import 'package:connectum/core/log/log.dart';
import 'ids.dart';

class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.convId,
    required this.kind,
    required this.payload,
    required this.refId,
    required this.status,
    required this.retryCount,
    required this.nextAttemptTs,
    required this.createdTs,
    this.lastError,
    this.cursorAtSend,
    this.attemptTs,
    this.cid,
    this.firstAttemptTs,
    this.isUnreadable = false,
  });

  final int id;
  final String convId;
  final String kind;
  final Map<String, dynamic> payload;
  final String refId;
  final String status;
  final int retryCount;
  final int nextAttemptTs;
  final int createdTs;
  final String? lastError;
  final String? cursorAtSend;
  final int? attemptTs;
  final String? cid;
  final int? firstAttemptTs;

  /// The stored payload could not be read; it is never sent.
  final bool isUnreadable;

  bool get isChat =>
      kind == 'message' ||
      kind == 'reply' ||
      kind == 'edit' ||
      kind == 'delete';

  bool get isSend => kind == 'message' || kind == 'reply';

  /// Only sends answered with an ack take a client id; the global room does not.
  bool get usesCid => isSend && cid != null && convId != 'global';

  /// The captions a draft waits to have filled (`waiting` of its payload).
  static List<String> waitingOf(String payloadJson) {
    try {
      final p = jsonDecode(payloadJson);
      final w = p is Map ? p['waiting'] : null;
      return w is List ? [for (final e in w) idText(e)] : const [];
    } on FormatException {
      return const [];
    }
  }

  static Map<String, dynamic>? _payloadOf(Object? raw) {
    final p = safeSync<Object?>('outbox_entry', () => jsonDecode(idText(raw)));
    return p is Map ? p.cast<String, dynamic>() : null;
  }

  factory OutboxEntry.fromRow(Map<String, Object?> r) {
    final payload = _payloadOf(r['payload_json']);
    return OutboxEntry._row(r, payload);
  }

  factory OutboxEntry._row(Map<String, Object?> r, Map<String, dynamic>? p) =>
      OutboxEntry(
        isUnreadable: p == null,
        id: intOf(r['id']),
        convId: idText(r['conv_id']),
        kind: idText(r['kind']),
        payload: p ?? <String, dynamic>{},
        refId: idText(r['ref_id']),
        status: idText(r['status']),
        retryCount: intOf(r['retry_count']),
        nextAttemptTs: intOf(r['next_attempt_ts']),
        createdTs: intOf(r['created_ts']),
        lastError: r['last_error'] as String?,
        cursorAtSend: r['cursor_at_send'] as String?,
        attemptTs: r['attempt_ts'] == null ? null : intOf(r['attempt_ts']),
        cid: r['cid'] as String?,
        firstAttemptTs: r['first_attempt_ts'] == null
            ? null
            : intOf(r['first_attempt_ts']),
      );
}
