import 'package:flutter/foundation.dart';

import 'package:connectum/core/log/log.dart';

/// The person's own conversation (My Work Space notes). It has no list row,
/// no unread count and no peer. A plain note is sent with `/self`; an
/// encrypted one carries an envelope for the person's own devices. A note is
/// never sent in plain text where the organisation requires encryption and
/// never reaches the global room. Edit, delete and reply have their own
/// commands (`/edit self`, `/delete self`, `/replyself`); save and pin go
/// through the marks repository (`msg.save`, `msg.pin`) and never through the
/// chat commands.
class SelfConversation {
  SelfConversation._();

  static const id = 'self';

  /// The longest plain note (the server's usual message limit).
  static const maxLength = 2000;

  static const tooLongText = 'A note can have at most $maxLength characters.';

  /// `fail_reason` of a note older than the server's memory of its client id.
  static const tooOld = 'older than 23 hours';

  /// `fail_reason` of a pending note that waits for encryption to be ready.
  static const waitingForEncryption = 'waiting:encryption';

  /// `fail_reason` of a note that waited more than [setupAfter] for encryption:
  /// the thread then says what to do (set encryption up on this phone).
  static const waitingForSetup = 'waiting:setup';

  /// How long a note waits quietly before the thread asks for setup.
  static const setupAfter = Duration(minutes: 2);

  /// The slow fallback between tries while a note waits for encryption (the
  /// events - a device registered, a sync done, a reconnect, a resume - try
  /// again at once).
  static const waitFallback = Duration(seconds: 60);

  static const setupNeededLine =
      "Encryption isn't ready on this phone. Tap to set it up";

  /// What the thread says when notes written before this phone was set up
  /// cannot be opened here.
  static const lockedNotesLine =
      'Some older notes are locked on this phone. Approve this phone from another device you use, or use your recovery code if you turned it on.';

  /// The most an encrypted note's envelope may hold (the server's cap).
  static const maxEnvelope = 120000;

  /// `fail_reason` of a sent note whose edit waits to reach the server (the
  /// new text shows at once with a clock instead of the tick).
  static const editPending = 'edit:pending';

  /// Notes have no edit window: Edit shows on every sent note whatever its
  /// age (direct chats and groups keep the server's 15 minutes). The server
  /// may still answer `expired` until it exempts self notes (requested, not
  /// confirmed); that edit is dropped without retry. Set this to true to bring
  /// the local check back.
  static const hasEditWindow = false;

  /// The server's `CHAT_EDIT_WINDOW_SEC` (900 s), counted to the moment it
  /// RECEIVES the edit. Used only while [hasEditWindow] is true.
  static const editWindow = Duration(minutes: 15);

  static bool isSelf(String convId) => convId == id;

  /// True while a note made at [noteTs] can be edited at [nowMs]: always,
  /// unless [hasEditWindow].
  static bool isInEditWindow(int noteTs, int nowMs) =>
      !hasEditWindow || nowMs - noteTs <= editWindow.inMilliseconds;

  /// The marks a note can take: they have their own client, so they are
  /// never refused here.
  static const markCommands = {'save', 'unsave', 'pin', 'unpin'};

  /// True when [what] for [convId] must be refused (a chat command that has
  /// no self version). Save and pin are built and never refused. Throws a
  /// [StateError] in a debug build; in a release build it writes one log line
  /// (no text) and returns true so the caller drops the attempt.
  static bool refuse(String convId, String what, {bool? isDebug}) {
    if (!isSelf(convId) || markCommands.contains(what)) return false;
    if (isDebug ?? kDebugMode) {
      throw StateError('Not built for the self conversation: $what');
    }
    AppLog.w('self_conversation', 'refused $what into self');
    return true;
  }
}
