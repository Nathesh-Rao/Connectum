import 'dart:convert';

import '../models/message.dart';
import 'ai_prompt.dart';

/// The chat as the model reads it: `formatTranscript()` of the web
/// (`chatReader.js`, section 3.3 of `reference/ai-chat/MOBILE_AI_IN_CHAT_FOLLOWUP.md`).
/// The time is the viewer's local time.
class AiTranscript {
  const AiTranscript(this.text, this.count);

  /// The text for the model. When there is nothing to summarise it is the
  /// web's "has no messages" sentence and [count] is 0.
  final String text;

  /// How many messages it holds.
  final int count;

  bool get isEmpty => count == 0;

  static const maxMessages = 300;
  static const maxChars = 60000;
  static const minLines = 20;
  static const lineChars = 600;
  static const replyChars = 60;
  static const valueChars = 200;

  /// [kind] is dm | group | host | global; [title] the chat's name.
  /// [nameOf] turns a username into what the model sees. [statusOf] gives the
  /// status of a submission by its number, when known.
  static AiTranscript build(
    List<Message> all, {
    required String kind,
    required String title,
    required DateTime? since,
    required String Function(String user) nameOf,
    String? Function(String submissionId)? statusOf,
  }) {
    final cutoff = since?.millisecondsSinceEpoch;
    final byId = {for (final m in all) m.msgId: m};
    final list = <(Message, String)>[];
    final sorted =
        all
            .where(
              (m) =>
                  !m.isDeleted &&
                  m.ts > 0 &&
                  !m.isEncryptedUnsupported &&
                  (cutoff == null || m.ts >= cutoff),
            )
            .toList()
          ..sort((a, b) => a.ts.compareTo(b.ts));
    for (final m in sorted) {
      final body = _body(m, statusOf);
      if (body.isEmpty) continue;
      list.add((m, _line(m, body, byId, nameOf)));
    }

    final shape = switch (kind) {
      'dm' => 'private chat with',
      'group' => 'group',
      'host' => 'host chat',
      _ => 'chat',
    };
    if (list.isEmpty) {
      final from = since == null ? '' : ' since ${AiPrompt.day(since)}';
      return AiTranscript('The $shape $title has no messages$from.', 0);
    }

    var kept = list.length > maxMessages
        ? list.sublist(list.length - maxMessages)
        : list;
    var chars = kept.fold<int>(0, (n, e) => n + e.$2.length + 1);
    while (chars > maxChars && kept.length > minLines) {
      chars -= kept.first.$2.length + 1;
      kept = kept.sublist(1);
    }

    final note = kept.length < list.length
        ? ' (only the newest ${kept.length} of ${list.length} are shown: '
              'older messages were not read)'
        : ' (the whole conversation)';
    final n = kept.length;
    final header =
        'CHAT: $shape $title - $n ${n == 1 ? 'message' : 'messages'}, '
        '${_stamp(kept.first.$1.ts)} to ${_stamp(kept.last.$1.ts)}$note. '
        "Times are the viewer's local time.";
    return AiTranscript('$header\n${kept.map((e) => e.$2).join('\n')}', n);
  }

  static String _line(
    Message m,
    String body,
    Map<String, Message> byId,
    String Function(String) nameOf,
  ) {
    final name = _name(m.sender, nameOf);
    final who = m.isMine ? '$name (you)' : name;
    final parent = m.replyTo == null ? null : byId[m.replyTo];
    final reply = parent == null || parent.isDeleted
        ? ''
        : ' (reply to ${_name(parent.sender, nameOf)}: '
              '"${_cut(_flat(parent.text), replyChars)}")';
    return '[${_stamp(m.ts)}] $who$reply: $body';
  }

  static String _name(String user, String Function(String) nameOf) {
    final name = nameOf(user).trim();
    return name.isEmpty ? 'someone' : name;
  }

  static String _body(Message m, String? Function(String)? statusOf) {
    if (m.kind != 'form') return _cut(_flat(m.text), lineChars);
    final form = _decode(m.formJson);
    if (form == null) {
      final text = _cut(_flat(m.text), valueChars);
      return text.isEmpty ? '' : '[form submission] $text';
    }
    final caption = _text(form['caption']).isNotEmpty
        ? _text(form['caption'])
        : _text(form['structure']).isNotEmpty
        ? _text(form['structure'])
        : 'Form';
    final id = _text(form['submissionId']);
    final number = id.isEmpty || id.startsWith('temp-') ? '' : id;
    final status = number.isEmpty ? null : statusOf?.call(number);
    final values = <String>[];
    final fields = form['fields'];
    if (fields is List) {
      for (final f in fields) {
        if (f is! Map) continue;
        final label = f['label'];
        final raw = label is String && label.trim().isNotEmpty
            ? label
            : f['value'];
        final value = _flat(_value(raw));
        if (value.isEmpty) continue;
        final name = _text(f['caption']).isNotEmpty
            ? _text(f['caption'])
            : _text(f['name']);
        values.add('${_flat(name)}: ${_cut(value, valueChars)}');
      }
    }
    return '[form submission] $caption'
        '${number.isEmpty ? '' : ' #$number'}'
        '${status == null || status.isEmpty ? '' : ' ($status)'}'
        ' - ${values.isEmpty ? 'no values' : values.join('; ')}';
  }

  static Map? _decode(String? json) {
    if (json == null) return null;
    try {
      final form = jsonDecode(json);
      return form is Map ? form : null;
    } on FormatException {
      return null;
    }
  }

  static String _text(Object? v) => v == null ? '' : '$v'.trim();

  /// A list is joined with `, `, an object is written as JSON.
  static String _value(Object? v) {
    if (v == null) return '';
    if (v is List) {
      return v.map(_value).where((e) => e.isNotEmpty).join(', ');
    }
    if (v is Map) return jsonEncode(v);
    return '$v';
  }

  static String _flat(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _cut(String text, int max) =>
      text.length > max ? '${text.substring(0, max)}…' : text;

  static String _stamp(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${AiPrompt.day(d)} ${two(d.hour)}:${two(d.minute)}';
  }
}
