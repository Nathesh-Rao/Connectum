import 'package:flutter/material.dart';

import '../../core/theme/app_tones.dart';
import '../../data/notifications/local_notification_rules.dart';
import 'models/feed_item.dart';
import 'notification_texts.dart';

/// The icon and colours of a feed item, derived at render time.
class NotificationStyle {
  const NotificationStyle(
    this.icon,
    this.tone, [
    this.category = NotificationTexts.categoryGeneral,
  ]);

  final IconData icon;
  final AppTone tone;

  /// The label of the category pill in the detail sheet.
  final String category;

  Color get color => tone.solid;
  Color get tint => tone.tint;

  /// The tint of the swipe background.
  Color get tintStrong => tone.tintStrong;

  /// Text and icons on the tints.
  Color get strong => tone.strong;
}

/// One rule: the item types (`actionType`, `icon` or `category` of the item)
/// and the keywords (start of a word in the title and message) that choose
/// [icon] and [tone].
class NotificationRule {
  const NotificationRule({
    required this.icon,
    required this.tone,
    this.category = NotificationTexts.categoryGeneral,
    this.types = const {},
    this.keywords = const [],
  });

  final IconData icon;
  final AppTone tone;
  final String category;
  final Set<String> types;
  final List<String> keywords;
}

/// The icon and tone of a feed item. To add a rule, put a [NotificationRule]
/// in [notificationRules]: the first rule that matches wins, so a more
/// specific rule goes above a general one.
///
/// 1. The item's `actionType`, then its `icon`, then its `category` are looked
///    up in the `types` of the rules.
/// 2. Else the title and message are matched against the `keywords`, ignoring
///    case. The message of an end-to-end item is not read.
/// 3. Else the bell in slate.
NotificationStyle styleFor(FeedItem item) {
  if (LocalNotificationRules.isGroupMessage(item)) {
    return const NotificationStyle(
      Icons.groups_rounded,
      AppTones.indigo,
      NotificationTexts.categoryMessages,
    );
  }
  for (final type in [item.actionType, item.icon, item.category]) {
    if (type == null) continue;
    final key = type.toLowerCase();
    for (final rule in notificationRules) {
      if (rule.types.contains(key)) {
        return NotificationStyle(rule.icon, rule.tone, rule.category);
      }
    }
  }
  final text = (item.isE2e ? item.title : '${item.title} ${item.message}')
      .toLowerCase();
  for (final rule in notificationRules) {
    for (final keyword in rule.keywords) {
      if (RegExp('\\b${RegExp.escape(keyword)}').hasMatch(text)) {
        return NotificationStyle(rule.icon, rule.tone, rule.category);
      }
    }
  }
  return const NotificationStyle(Icons.notifications_rounded, AppTones.slate);
}

const notificationRules = [
  // Outcomes first: "request rejected" is an error, not a request.
  NotificationRule(
    icon: Icons.error_rounded,
    tone: AppTones.red,
    keywords: ['rejected', 'failed', 'error'],
  ),
  NotificationRule(
    icon: Icons.check_circle_rounded,
    tone: AppTones.green,
    keywords: ['verified', 'success', 'completed', 'approved'],
  ),
  NotificationRule(
    icon: Icons.assignment_rounded,
    tone: AppTones.purple,
    category: NotificationTexts.categorySubmissions,
    types: {'submissions', 'submission'},
    keywords: ['submission', 'submitted'],
  ),
  NotificationRule(
    icon: Icons.confirmation_number_rounded,
    tone: AppTones.purple,
    category: NotificationTexts.categoryTickets,
    types: {'tickets', 'ticket', 'status', 'confirmation_number'},
    keywords: ['ticket'],
  ),
  NotificationRule(
    icon: Icons.draw_rounded,
    tone: AppTones.purple,
    category: NotificationTexts.categorySignatures,
    keywords: ['signed', 'sign', 'signature'],
  ),
  NotificationRule(
    icon: Icons.fact_check_rounded,
    tone: AppTones.blue,
    category: NotificationTexts.categoryApprovals,
    types: {'approvals', 'approval', 'request', 'fact_check'},
    keywords: ['approval', 'approve', 'request'],
  ),
  NotificationRule(
    icon: Icons.task_alt_rounded,
    tone: AppTones.teal,
    category: NotificationTexts.categoryTasks,
    types: {'tasks', 'task', 'task_alt'},
    keywords: ['task', 'to-do', 'todo'],
  ),
  NotificationRule(
    icon: Icons.alternate_email_rounded,
    tone: AppTones.blue,
    category: NotificationTexts.categoryMentions,
    types: {'mention', 'alternate_email'},
    keywords: ['mention'],
  ),
  NotificationRule(
    icon: Icons.chat_bubble_rounded,
    tone: AppTones.indigo,
    category: NotificationTexts.categoryMessages,
    types: {
      'open_chat',
      'open_message',
      'messages',
      'message',
      'chat',
      'group',
    },
    keywords: ['message', 'chat'],
  ),
  NotificationRule(
    icon: Icons.alarm_rounded,
    tone: AppTones.red,
    category: NotificationTexts.categoryReminders,
    types: {'reminders', 'reminder', 'alarm'},
    keywords: ['reminder', 'due', 'deadline', 'closing', 'expire'],
  ),
  NotificationRule(
    icon: Icons.campaign_rounded,
    tone: AppTones.indigo,
    category: NotificationTexts.categoryAnnouncements,
    types: {'broadcast', 'campaign'},
    keywords: ['broadcast', 'announcement'],
  ),
  NotificationRule(
    icon: Icons.person_add_rounded,
    tone: AppTones.blue,
    category: NotificationTexts.categoryTeam,
    keywords: ['added', 'joined', 'invite'],
  ),
  NotificationRule(
    icon: Icons.mic_rounded,
    tone: AppTones.teal,
    category: NotificationTexts.categoryRecordings,
    keywords: ['recording', 'upload'],
  ),
  NotificationRule(
    icon: Icons.shield_rounded,
    tone: AppTones.red,
    category: NotificationTexts.categorySecurity,
    types: {'security', 'lock'},
    keywords: ['login', 'security'],
  ),
  NotificationRule(
    icon: Icons.api_rounded,
    tone: AppTones.slate,
    category: NotificationTexts.categoryApi,
    types: {'api'},
  ),
  NotificationRule(
    icon: Icons.settings_rounded,
    tone: AppTones.slate,
    category: NotificationTexts.categorySystem,
    types: {'system'},
  ),
];
