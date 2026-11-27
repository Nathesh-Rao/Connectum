/// The `msg.*` commands of saved and pinned messages (`sd_msgmarks.erl`) and
/// their events: the only place they are written. WebSocket only
/// (`/sd <action> {json}`); they count against the 30 commands per 10 s of the
/// connection like any other.
///
/// Shapes (BE `sd_msgmarks.erl`, `connectum_selfmsg_test.mjs`):
/// - `msg.save {conv, id}` -> `{saved:true}`; saving again changes nothing.
/// - `msg.unsave {id}` -> `{saved:false}` (no `conv`; unsaving what is not
///   saved is fine).
/// - `msg.saved {ids:true}` -> `{ids:[...]}`, or `{limit?, offset?}` ->
///   `{items:[{id, conv, from, text, ts, kind, savedTs}], total, limit,
///   offset}`.
/// - `msg.pin {conv, id}` -> `{pinned:true, count}`; pinning again changes
///   nothing.
/// - `msg.unpin {conv, id}` -> `{pinned:false, count}`.
/// - `msg.pins {conv}` -> `{pins:[{id, by, ts, message:{id, from, text, ts,
///   kind}}], max}`, newest pin first.
/// `conv` is `dm:<user>`, `group:<name>`, `global` (save only) or `self`, the
/// caller's own conversation. Errors: `not_found` (no such message in that
/// conversation, or deleted), `invalid` (a form, a missing id, pins in the
/// general room), `limit` (500 saved, 10 pinned), `rate_limited`.
class MarkCmd {
  MarkCmd._();

  static const save = 'msg.save';
  static const unsave = 'msg.unsave';
  static const saved = 'msg.saved';
  static const pin = 'msg.pin';
  static const unpin = 'msg.unpin';
  static const pins = 'msg.pins';

  static Map<String, dynamic> saveArgs(String conv, int id) => {
    'conv': conv,
    'id': id,
  };

  static Map<String, dynamic> unsaveArgs(int id) => {'id': id};

  static Map<String, dynamic> pinArgs(String conv, int id) => {
    'conv': conv,
    'id': id,
  };

  static Map<String, dynamic> pinsArgs(String conv) => {'conv': conv};

  static const savedIdsArgs = <String, dynamic>{'ids': true};
}

class MarkEvents {
  MarkEvents._();

  /// To every device of the person: `{id, saved}`.
  static const savedChanged = 'saved_changed';

  /// To everyone in the conversation: `{conv, id, pinned, by}`. For `self` it
  /// reaches every device of the person, this one too.
  static const pinsChanged = 'pins_changed';

  /// `{messageId}`: the note and its marks are gone.
  static const selfDeleted = 'self_deleted';
}
