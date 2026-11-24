// Port of the web's `recordTone.js`: what a record's colour says. Pure Dart.

/// Where a record stands for the person looking at it.
enum InboxState { completed, rejected, waiting, pending, assigned }

/// The words of each state (the web's `STATE_WORDS`).
const inboxStateWords = {
  InboxState.completed: 'Completed',
  InboxState.rejected: 'Declined',
  InboxState.waiting: 'Waiting for approval',
  InboxState.pending: 'Pending: waiting for action',
  InboxState.assigned: 'Assigned: open, with someone else',
};

enum InboxPriority { high, medium, low }

/// A field that says how important a record is, by its name or caption.
final signalField = RegExp(
  r'(priorit|severit|urgen|importan|critical|risk)',
  caseSensitive: false,
);

final _levels = <(InboxPriority, RegExp)>[
  (
    InboxPriority.high,
    RegExp(
      r'^(highest|very high|high|urgent|critical|blocker|severe|major|p0|p1|sev ?1)$',
    ),
  ),
  (
    InboxPriority.medium,
    RegExp(r'^(medium|moderate|normal|average|med|p2|sev ?2)$'),
  ),
  (
    InboxPriority.low,
    RegExp(r'^(lowest|very low|low|minor|trivial|p3|p4|sev ?3|sev ?4)$'),
  ),
];

final _wentWrong = RegExp(
  r'^(rejected|declined|blocked|failed|overdue|cancelled|canceled)$',
);
final _noiseWords = RegExp(r'\b(priority|severity|urgency|level)\b');

/// An answer as plain lower-case words ("High priority" -> "high"); anything
/// that is not text or a number is nothing.
String answerWord(Object? v) {
  final first = v is List ? (v.isEmpty ? null : v.first) : v;
  if (first is! String && first is! num) return '';
  return first
      .toString()
      .toLowerCase()
      .replaceAll(_noiseWords, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// How important the record says it is, or null. [fields] is field name ->
/// caption; [labels] (what a list shows) are read before the stored value.
InboxPriority? priorityOf({
  Map<String, dynamic> values = const {},
  Map<String, dynamic> labels = const {},
  Map<String, String> fields = const {},
}) {
  for (final name in values.keys) {
    if (!signalField.hasMatch(name) &&
        !signalField.hasMatch(fields[name] ?? '')) {
      continue;
    }
    final word = answerWord(labels[name] ?? values[name]);
    for (final (level, re) in _levels) {
      if (re.hasMatch(word)) return level;
    }
  }
  return null;
}

List<String> _names(String holder) => [
  for (final n in holder.split(','))
    if (n.replaceFirst('@', '').trim().toLowerCase().isNotEmpty)
      n.replaceFirst('@', '').trim().toLowerCase(),
];

/// Port of `recordState`. [holder] is "a, @b" when shared; [via] says how the
/// team list ties the record to the team; [view] is the status the person
/// chose to look at ('pending' | 'assigned' | 'completed' | '').
InboxState recordStateOf({
  bool isFinal = false,
  bool isWaiting = false,
  bool isDeclined = false,
  String statusText = '',
  String holder = '',
  List<String> via = const [],
  String me = '',
  String view = '',
}) {
  if (isFinal) return InboxState.completed;
  if (isDeclined || _wentWrong.hasMatch(answerWord(statusText))) {
    return InboxState.rejected;
  }
  if (isWaiting) return InboxState.waiting;
  if (view == 'pending') return InboxState.pending;
  if (view == 'assigned') return InboxState.assigned;
  if (me.isNotEmpty && _names(holder).contains(me.toLowerCase())) {
    return InboxState.pending;
  }
  if (via.contains('holder')) return InboxState.pending;
  return InboxState.assigned;
}
