/// The words of the notifications feature, in one place.
class NotificationTexts {
  NotificationTexts._();

  static const screenTitle = 'Notifications';
  static const filterAll = 'All';
  static const filterHigh = 'High';
  static const filterMedium = 'Medium';
  static const filterLow = 'Low';
  static const filterResolved = 'Resolved';
  static const unreadOnly = 'Unread only';
  static const markAllRead = 'Mark all read';
  static const markAllResolved = 'Mark all resolved';
  static const clearResolved = 'Clear resolved';
  static const notifyGroups = 'Notify for group messages';
  static const markRead = 'Mark read';
  static const markUnread = 'Mark unread';
  static const resolve = 'Resolve';
  static const dismiss = 'Dismiss';
  static const menu = 'More';

  static const emptyTitle = 'Nothing here';
  static const emptyMessage = 'New notifications will show up here.';
  static const emptyUnread = 'You are all caught up.';
  static const errorMessage = "Couldn't load your notifications.";
  static const encrypted = 'Encrypted message';
  static const newMessage = 'New message';
  static const actionFailed = "Couldn't do that. Try again.";

  static const permissionTitle = 'Stay in the loop';
  static const permissionBody =
      'Allow notifications so Connectum can tell you about new messages and '
      'approvals while the app is in the background.';
  static const permissionAllow = 'Allow notifications';
  static const permissionLater = 'Not now';
  static const permissionOffRow = 'Notifications are off on this phone.';
  static const permissionTurnOn = 'Turn on';
  static const permissionOpenSettings = 'Open settings';

  // Android channels: id, name, description.
  static const channels = {
    'messages': ('Messages', 'New direct and group messages and mentions.'),
    'approvals': (
      'Approvals',
      'Requests waiting for you and the answers to yours.',
    ),
    'tasks': ('Tasks', 'Tasks and tickets assigned to you or changed.'),
    'system': ('System', 'Announcements, reminders and other notices.'),
    'security': (
      'Security',
      'Sign-ins, new devices and changes to your account.',
    ),
  };
}
