import 'dart:async';

import '../models/ids.dart';

/// The answer to one `#` line, read from the chat-socket frames.
class CommandReply {
  const CommandReply({
    this.isOk = true,
    this.code = '',
    this.text = '',
    this.usage = '',
    this.suggestions = const [],
    this.frame = const {},
    this.isDuplicate = false,
  });

  final bool isOk;
  final String code;
  final String text;
  final String usage;
  final List<String> suggestions;
  final Map<String, dynamic> frame;

  /// `duplicate:true` is a normal ack: the server already did it.
  final bool isDuplicate;

  /// Events a command answers with besides what the catalogue lists.
  static const _extra = {
    'addmember': {'group_invite_pending'},
    'invitegroup': {'group_invite_pending'},
  };

  /// Reads [frame] as the answer to command [name] (whose catalogue `reply`
  /// types are [replies]), or null when it is about something else: a chat
  /// error of a conversation, a message, any unrelated event.
  static CommandReply? fromFrame(
    Map<String, dynamic> frame, {
    required String name,
    List<String> replies = const [],
  }) {
    final type = frame['type'];
    if (type == 'error') {
      if (frame['conv'] != null) return null;
      return CommandReply(
        isOk: false,
        code: idText(frame['code']),
        text: idText(frame['text']),
        usage: idText(frame['usage']),
        suggestions: [
          for (final s in (frame['suggestions'] as List? ?? const []))
            idText(s),
        ],
        frame: frame,
      );
    }
    if (type == 'sd') {
      if (idText(frame['reqId']) != '#$name') return null;
      if (frame['ok'] == true) {
        return CommandReply(
          frame: (frame['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
      }
      final error = (frame['error'] as Map?) ?? const {};
      return CommandReply(
        isOk: false,
        code: idText(error['code']),
        text: idText(error['message'] ?? error['text']),
        frame: frame,
      );
    }
    final wanted = {...replies, ...?_extra[name]}..remove('sd');
    if (wanted.contains(type)) {
      return CommandReply(
        frame: frame,
        isDuplicate: frame['duplicate'] == true,
      );
    }
    return null;
  }

  /// What to tell the person for a failed line.
  String get message {
    if (code == 'rate_limited' || text.contains('Too many commands')) {
      return 'Too many commands. Wait a moment and try again.';
    }
    if (code == 'cid_unsupported') return "That command can't be repeated.";
    if (text.isNotEmpty) return text;
    return switch (code) {
      'invalid_encoding' => 'That command is not valid text.',
      'internal' => 'Something went wrong running that command.',
      _ => "That didn't work.",
    };
  }
}

/// One page of `/cmdcomplete` suggestions.
class CommandSuggestions {
  const CommandSuggestions({
    required this.input,
    required this.reqId,
    this.kind = 'none',
    this.token = '',
    this.command = '',
    this.argName = '',
    this.argIndex = 0,
    this.items = const [],
    this.page = 1,
    this.hasMore = false,
    this.total = 0,
  });

  final String input;
  final int reqId;

  /// `command`, `arg`, `text` or `none`.
  final String kind;
  final String token;
  final String command;
  final String argName;
  final int argIndex;
  final List<CommandSuggestion> items;
  final int page;
  final bool hasMore;
  final int total;

  factory CommandSuggestions.fromFrame(Map<String, dynamic> e) {
    final arg = e['arg'] is Map ? (e['arg'] as Map) : const {};
    return CommandSuggestions(
      input: idText(e['input']),
      reqId: intOf(e['reqId']),
      kind: idText(e['kind']).isEmpty ? 'none' : idText(e['kind']),
      token: idText(e['token']),
      command: idText(e['command']),
      argName: idText(arg['name']),
      argIndex: intOf(arg['index']),
      items: [
        for (final i in (e['items'] as List? ?? const []))
          if (i is Map) CommandSuggestion.fromJson(i.cast<String, dynamic>()),
      ],
      page: intOf(e['page']) == 0 ? 1 : intOf(e['page']),
      hasMore: e['hasMore'] == true,
      total: intOf(e['total']),
    );
  }
}

class CommandSuggestion {
  const CommandSuggestion({
    required this.value,
    this.label = '',
    this.hint = '',
  });

  final String value;
  final String label;
  final String hint;

  factory CommandSuggestion.fromJson(Map<String, dynamic> j) =>
      CommandSuggestion(
        value: idText(j['value']),
        label: idText(j['label']),
        hint: idText(j['hint']),
      );
}

/// Asks the server for suggestions while the person types: waits [delay]
/// after the last change, numbers every request, and passes on only the
/// answer to the newest one.
class CommandSuggester {
  CommandSuggester(
    this._fetch, {
    this.delay = const Duration(milliseconds: 150),
  });

  static const maxBytes = 512;
  static const pageSize = 10;

  final Future<CommandSuggestions?> Function(String input, int page, int reqId)
  _fetch;
  final Duration delay;

  /// Called with the newest answer only.
  void Function(CommandSuggestions result, {required bool isMore})? onResult;

  Timer? _timer;
  int _latest = 0;
  bool _isClosed = false;

  int get latestReqId => _latest;

  /// True when [input] fits the 512-byte limit of the server.
  static bool fits(String input) => _utf8Length(input) <= maxBytes;

  static int _utf8Length(String s) {
    var n = 0;
    for (final r in s.runes) {
      n += r < 0x80
          ? 1
          : r < 0x800
          ? 2
          : r < 0x10000
          ? 3
          : 4;
    }
    return n;
  }

  /// [input] is the text up to the caret.
  void request(String input, {int page = 1}) {
    _timer?.cancel();
    final reqId = ++_latest;
    if (!fits(input)) return;
    _timer = Timer(delay, () => _send(input, page, reqId));
  }

  Future<void> _send(String input, int page, int reqId) async {
    final result = await _fetch(input, page, reqId);
    if (_isClosed || result == null || reqId != _latest) return;
    onResult?.call(result, isMore: page > 1);
  }

  /// Drops whatever is waiting or on its way.
  void cancel() {
    _timer?.cancel();
    _latest++;
  }

  void dispose() {
    _isClosed = true;
    _timer?.cancel();
  }
}
