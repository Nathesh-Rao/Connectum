import '../../../data/models/ids.dart';

/// The server keeps this many feed items per person, and so does the app.
const feedCap = 300;

/// The server clips a feed message to this many characters.
const feedMessageMax = 200;

/// One workspace feed item (`feed.list`, `feed_item`). Every field but [id]
/// may be missing; unknown fields stay in [extra].
class FeedItem {
  const FeedItem({
    required this.id,
    this.priority = 'low',
    this.category,
    this.title = '',
    this.message = '',
    this.ts = 0,
    this.icon,
    this.isRead = false,
    this.actionType,
    this.actionLabel,
    this.chatId,
    this.ref = const {},
    this.count = 1,
    this.isResolved = false,
    this.resolvedTs,
    this.isE2e = false,
    this.from,
    this.chat,
    this.outcome,
    this.source,
    this.httpStatus,
    this.data,
    this.via,
    this.extra = const {},
  });

  final String id;

  /// high | medium | low | resolved
  final String priority;
  final String? category;
  final String title;
  final String message;
  final int ts;
  final String? icon;
  final bool isRead;
  final String? actionType;
  final String? actionLabel;
  final String? chatId;
  final Map<String, dynamic> ref;
  final int count;
  final bool isResolved;
  final int? resolvedTs;

  /// The message is a whole `e2e1:` envelope the device has to open.
  final bool isE2e;
  final String? from;
  final Map<String, dynamic>? chat;

  // API-message items.
  final String? outcome;
  final String? source;
  final int? httpStatus;
  final Object? data;
  final String? via;

  final Map<String, dynamic> extra;

  String? get messageId {
    final v = ref['messageId'];
    return v == null ? null : idText(v);
  }

  String? get deviceId {
    final v = ref['deviceId'];
    return v == null ? null : idText(v);
  }

  bool get isHigh => priority == 'high';

  /// The conversation this item belongs to (`dm:<user>`, `group:<name>`), if
  /// it names one.
  String? get conversationId {
    final fromId = conversationOfChatId(chatId);
    if (fromId != null) return fromId;
    final name = chat?['with'] ?? chat?['group'];
    if (name == null || '$name'.isEmpty) return null;
    return switch (chat?['scope']) {
      'dm' => 'dm:$name',
      'group' => 'group:$name',
      _ => null,
    };
  }

  /// `user-<name>` is a direct chat, `room-<group>` a group.
  static String? conversationOfChatId(String? chatId) {
    if (chatId == null) return null;
    if (chatId.startsWith('user-') && chatId.length > 5) {
      return 'dm:${chatId.substring(5)}';
    }
    if (chatId.startsWith('room-') && chatId.length > 5) {
      return 'group:${chatId.substring(5)}';
    }
    return null;
  }

  static const _known = {
    'id',
    'priority',
    'category',
    'title',
    'message',
    'ts',
    'icon',
    'read',
    'actionType',
    'actionLabel',
    'chatId',
    'ref',
    'count',
    'resolved',
    'resolvedTs',
    'e2e',
    'from',
    'chat',
    'outcome',
    'source',
    'httpStatus',
    'data',
    'via',
  };

  /// Null when the map has no usable id.
  static FeedItem? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = idText(json['id']);
    if (id.isEmpty) return null;
    final isResolved = json['resolved'] == true;
    final message = _text(json['message']);
    final ref = json['ref'];
    final chat = json['chat'];
    return FeedItem(
      id: id,
      priority: _text(json['priority']).isEmpty
          ? (isResolved ? 'resolved' : 'low')
          : _text(json['priority']),
      category: _textOrNull(json['category']),
      title: _text(json['title']),
      message: json['e2e'] == true ? message : clip(message, feedMessageMax),
      ts: intOf(json['ts']),
      icon: _textOrNull(json['icon']),
      isRead: json['read'] == true,
      actionType: _textOrNull(json['actionType']),
      actionLabel: _textOrNull(json['actionLabel']),
      chatId: _textOrNull(json['chatId']),
      ref: ref is Map ? ref.cast<String, dynamic>() : const {},
      count: json['count'] == null ? 1 : intOf(json['count']).clamp(1, 1 << 30),
      isResolved: isResolved,
      resolvedTs: json['resolvedTs'] == null ? null : intOf(json['resolvedTs']),
      isE2e: json['e2e'] == true,
      from: _textOrNull(json['from']),
      chat: chat is Map ? chat.cast<String, dynamic>() : null,
      outcome: _textOrNull(json['outcome']),
      source: _textOrNull(json['source']),
      httpStatus: json['httpStatus'] == null ? null : intOf(json['httpStatus']),
      data: json['data'],
      via: _textOrNull(json['via']),
      extra: {
        for (final e in json.entries)
          if (!_known.contains(e.key)) '${e.key}': e.value,
      },
    );
  }

  FeedItem copyWith({
    String? priority,
    bool? isRead,
    bool? isResolved,
    int? resolvedTs,
    String? message,
  }) => FeedItem(
    id: id,
    priority: priority ?? this.priority,
    category: category,
    title: title,
    message: message ?? this.message,
    ts: ts,
    icon: icon,
    isRead: isRead ?? this.isRead,
    actionType: actionType,
    actionLabel: actionLabel,
    chatId: chatId,
    ref: ref,
    count: count,
    isResolved: isResolved ?? this.isResolved,
    resolvedTs: resolvedTs ?? this.resolvedTs,
    isE2e: isE2e,
    from: from,
    chat: chat,
    outcome: outcome,
    source: source,
    httpStatus: httpStatus,
    data: data,
    via: via,
    extra: extra,
  );

  static String clip(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max - 1).trimRight()}…';

  static String _text(Object? v) => v == null ? '' : '$v';

  static String? _textOrNull(Object? v) {
    final t = _text(v);
    return t.isEmpty ? null : t;
  }
}

/// `feed.summary` and the `counts` in every feed answer and event.
class FeedCounts {
  const FeedCounts({
    this.high = 0,
    this.medium = 0,
    this.low = 0,
    this.resolved = 0,
    this.unread = 0,
    this.total = 0,
  });

  static const zero = FeedCounts();

  final int high;
  final int medium;
  final int low;
  final int resolved;
  final int unread;
  final int total;

  static FeedCounts? tryParse(Object? json) {
    if (json is! Map) return null;
    return FeedCounts(
      high: intOf(json['high']),
      medium: intOf(json['medium']),
      low: intOf(json['low']),
      resolved: intOf(json['resolved']),
      unread: intOf(json['unread']),
      total: intOf(json['total']),
    );
  }

  int forPriority(String priority) => switch (priority) {
    'high' => high,
    'medium' => medium,
    'low' => low,
    'resolved' => resolved,
    _ => total,
  };
}
