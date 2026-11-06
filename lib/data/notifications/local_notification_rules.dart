import '../../features/notifications/models/feed_item.dart';

/// What to do with a live `feed_item`.
enum NotificationShow { none, system }

/// The decision and the reason behind it, for the log.
typedef NotificationDecision = ({NotificationShow show, String reason});

/// The rules for when a feed item becomes a notification. Pure. Foreground
/// and background are the same: the system notification is the only trigger.
class LocalNotificationRules {
  LocalNotificationRules._();

  /// The words of a local notification are clipped to this.
  static const bodyMax = 100;

  /// [mutedConversations] and [openConversationId] are conversation ids
  /// (`dm:x`, `group:y`). A low item notifies only when it is a group message
  /// (see [isGroupMessage]) and [shouldNotifyGroups] is on.
  static NotificationShow decide(
    FeedItem item, {
    required String? myUser,
    required Set<String> mutedConversations,
    required String? openConversationId,
    bool shouldNotifyGroups = true,
  }) => explain(
    item,
    myUser: myUser,
    mutedConversations: mutedConversations,
    openConversationId: openConversationId,
    shouldNotifyGroups: shouldNotifyGroups,
  ).show;

  /// [decide] with the reason, e.g. `skipped: muted`.
  static NotificationDecision explain(
    FeedItem item, {
    required String? myUser,
    required Set<String> mutedConversations,
    required String? openConversationId,
    bool shouldNotifyGroups = true,
  }) {
    const none = NotificationShow.none;
    if (item.isRead || item.isResolved) {
      return (show: none, reason: 'skipped: read or resolved');
    }
    final from = item.from;
    if (from != null &&
        myUser != null &&
        from.toLowerCase() == myUser.toLowerCase()) {
      return (show: none, reason: 'skipped: own action');
    }
    final conversation = item.conversationId;
    if (conversation != null) {
      if (mutedConversations.contains(conversation)) {
        return (show: none, reason: 'skipped: muted');
      }
      if (conversation == openConversationId) {
        return (show: none, reason: 'skipped: open conversation');
      }
    }
    if (item.priority == 'low') {
      if (!isGroupMessage(item)) {
        return (show: none, reason: 'skipped: low severity');
      }
      if (!shouldNotifyGroups) {
        return (show: none, reason: 'skipped: group switch off');
      }
    }
    return (show: NotificationShow.system, reason: 'shown');
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
