import 'ids.dart';

/// The marks of one message: saved (mine alone) and pinned. What shows is the
/// person's last wish when it has not reached the server yet ([wantSaved],
/// [wantPinned]), else what the server said.
class MessageMark {
  const MessageMark({
    required this.convId,
    required this.msgId,
    this.isConfirmedSaved = false,
    this.isConfirmedPinned = false,
    this.wantSaved,
    this.wantPinned,
    this.pinnedBy = '',
    this.pinnedTs = 0,
    this.savedTs = 0,
    this.preview = '',
  });

  final String convId;
  final String msgId;
  final bool isConfirmedSaved;
  final bool isConfirmedPinned;

  /// A save or unsave that waits to reach the server (null: none).
  final bool? wantSaved;
  final bool? wantPinned;
  final String pinnedBy;
  final int pinnedTs;
  final int savedTs;

  /// The words the server gave for a pin (empty when it is an envelope or
  /// there are none); the note's own text is used when it is on the phone.
  final String preview;

  bool get isSaved => wantSaved ?? isConfirmedSaved;
  bool get isPinned => wantPinned ?? isConfirmedPinned;
  bool get isWaiting => wantSaved != null || wantPinned != null;

  factory MessageMark.fromRow(Map<String, Object?> r) => MessageMark(
    convId: idText(r['conv_id']),
    msgId: idText(r['msg_id']),
    isConfirmedSaved: intOf(r['is_saved']) == 1,
    isConfirmedPinned: intOf(r['is_pinned']) == 1,
    wantSaved: r['want_saved'] == null ? null : intOf(r['want_saved']) == 1,
    wantPinned: r['want_pinned'] == null ? null : intOf(r['want_pinned']) == 1,
    pinnedBy: idText(r['pinned_by']),
    pinnedTs: intOf(r['pinned_ts']),
    savedTs: intOf(r['saved_ts']),
    preview: idText(r['preview']),
  );
}
