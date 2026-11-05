import '../../features/notifications/models/feed_item.dart';

/// What to do with a live `feed_item`.
enum NotificationShow { none, system, inApp }

/// The rules for when a feed item becomes a notification. Pure.
class LocalNotificationRules {
  LocalNotificationRules._();

  /// The words of a local notification are clipped to this.
  static const bodyMax = 100;

  /// [isForeground] the app is on screen; [mutedConversations] and
  /// [openConversationId] are conversation ids (`dm:x`, `group:y`).
  /// A background item becomes a system notification; a foreground one an
  /// in-app notice for high and medium items only. A low group message
  /// (see [isGroupMessage]) also notifies in the background when
  /// [shouldNotifyGroups] is on.
  static NotificationShow decide(
    FeedItem item, {
    required bool isForeground,
    required String? myUser,
    required Set<String> mutedConversations,
    required String? openConversationId,
    bool shouldNotifyGroups = true,
  }) {
    if (item.isRead || item.isResolved) return NotificationShow.none;
    final from = item.from;
    if (from != null &&
        myUser != null &&
        from.toLowerCase() == myUser.toLowerCase()) {
      return NotificationShow.none;
    }
    final conversation = item.conversationId;
    if (conversation != null) {
      if (mutedConversations.contains(conversation)) {
        return NotificationShow.none;
      }
      if (conversation == openConversationId) return NotificationShow.none;
    }
    final isLow = item.priority == 'low';
    if (isForeground) {
      return isLow ? NotificationShow.none : NotificationShow.inApp;
    }
    if (isLow && !(shouldNotifyGroups && isGroupMessage(item))) {
      return NotificationShow.none;
    }
    return NotificationShow.system;
  }

  /// A message in a group: `open_chat` with a `room-` chat id.
  static bool isGroupMessage(FeedItem item) =>
      item.actionType == 'open_chat' &&
      (item.chatId?.startsWith('room-') ?? false);

  /// Android channel id for an item.
  static String channelOf(FeedItem item) {
    final action = item.actionType;
    if (item.category == 'security') return 'security';
    if (item.category == 'messages' ||
        action == 'open_chat' ||
        action == 'open_message') {
      return 'messages';
    }
    if (item.category == 'approvals' || action == 'approvals') {
      return 'approvals';
    }
    if (action == 'tickets' ||
        action == 'submissions' ||
        action == 'task' ||
        action == 'tasks' ||
        item.category == 'submissions') {
      return 'tasks';
    }
    return 'system';
  }

  /// A stable, positive 31-bit id for an item: the same item always replaces
  /// its own notification.
  static int notificationId(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
