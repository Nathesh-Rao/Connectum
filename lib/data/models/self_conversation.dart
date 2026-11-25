import 'package:flutter/foundation.dart';

import '../../core/log/app_log.dart';

/// The person's own conversation (My Work Space notes). It has no list row,
/// no unread count and no peer. Phase 1 only receives: nothing may be queued
/// or sent into it until the send rule exists (an encrypted organisation must
/// never get a plain note and a note must never reach the global room).
class SelfConversation {
  SelfConversation._();

  static const id = 'self';

  static bool isSelf(String convId) => convId == id;

  /// True when a send, edit or queue entry for [convId] must be refused.
  /// Throws a [StateError] in a debug build; in a release build it writes one
  /// log line (no text) and returns true so the caller drops the attempt.
  static bool refuse(String convId, String what, {bool? isDebug}) {
    if (!isSelf(convId)) return false;
    if (isDebug ?? kDebugMode) {
      throw StateError('Sending into the self conversation is not built: $what');
    }
    AppLog.w('self_conversation', 'refused $what into self');
    return true;
  }
}
