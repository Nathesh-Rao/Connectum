import 'dart:math' as math;

import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/notification_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem _item({
  String title = '',
  String message = '',
  String? actionType,
  String? icon,
  String? category,
  bool isE2e = false,
}) => FeedItem(
  id: 'a',
  title: title,
  message: message,
  actionType: actionType,
  icon: icon,
  category: category,
  isE2e: isE2e,
);

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final hi = math.max(_luminance(a), _luminance(b));
  final lo = math.min(_luminance(a), _luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('by type', () {
    test('actionType', () {
      expect(
        styleFor(_item(actionType: 'approvals')).icon,
        Icons.fact_check_rounded,
      );
      expect(
        styleFor(_item(actionType: 'tickets')).icon,
        Icons.confirmation_number_rounded,
      );
      expect(
        styleFor(_item(actionType: 'submissions')).icon,
        Icons.assignment_rounded,
      );
      expect(
        styleFor(_item(actionType: 'open_chat')).icon,
        Icons.chat_bubble_rounded,
      );
    });

    test('icon and category', () {
      expect(styleFor(_item(icon: 'task_alt')).tone, AppTones.teal);
      expect(styleFor(_item(icon: 'alternate_email')).tone, AppTones.blue);
      expect(styleFor(_item(category: 'reminders')).icon, Icons.alarm_rounded);
      expect(styleFor(_item(category: 'security')).icon, Icons.shield_rounded);
      expect(styleFor(_item(category: 'system')).icon, Icons.settings_rounded);
    });

    test('actionType beats icon, icon beats category', () {
      expect(
        styleFor(_item(actionType: 'tickets', icon: 'task_alt')).icon,
        Icons.confirmation_number_rounded,
      );
      expect(
        styleFor(_item(icon: 'task_alt', category: 'system')).icon,
        Icons.task_alt_rounded,
      );
    });

    test('a type beats the words', () {
      expect(
        styleFor(_item(actionType: 'approvals', title: 'Ticket 4')).icon,
        Icons.fact_check_rounded,
      );
    });

    test('a group message is the groups icon', () {
      final style = styleFor(
        const FeedItem(
          id: 'g',
          category: 'messages',
          actionType: 'open_chat',
          chatId: 'room-team',
        ),
      );
      expect(style.icon, Icons.groups_rounded);
    });
  });

  group('by keyword', () {
    const cases = {
      'Form submitted': Icons.assignment_rounded,
      'New ticket': Icons.confirmation_number_rounded,
      'Document signed': Icons.draw_rounded,
      'Approval needed': Icons.fact_check_rounded,
      'Leave request': Icons.fact_check_rounded,
      'A task for you': Icons.task_alt_rounded,
      'Your to-do list': Icons.task_alt_rounded,
      'Sam mentioned you': Icons.alternate_email_rounded,
      'New chat': Icons.chat_bubble_rounded,
      'Due tomorrow': Icons.alarm_rounded,
      'Registration closing': Icons.alarm_rounded,
      'Pass will expire': Icons.alarm_rounded,
      'Announcement': Icons.campaign_rounded,
      'Import completed': Icons.check_circle_rounded,
      'Request approved': Icons.check_circle_rounded,
      'Upload failed': Icons.error_rounded,
      'Request rejected': Icons.error_rounded,
      'Priya joined': Icons.person_add_rounded,
      'Recording saved': Icons.mic_rounded,
      'New login': Icons.shield_rounded,
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(styleFor(_item(title: e.key)).icon, e.value));
    }

    test('reads the message too', () {
      expect(
        styleFor(_item(title: 'Hello', message: 'Your ticket moved')).icon,
        Icons.confirmation_number_rounded,
      );
    });

    test('ignores case', () {
      expect(
        styleFor(_item(title: 'NEW TICKET')).icon,
        Icons.confirmation_number_rounded,
      );
    });

    test('matches the start of a word only', () {
      expect(
        styleFor(_item(title: 'Design review')).icon,
        isNot(Icons.draw_rounded),
      );
    });

    test('the first rule wins', () {
      expect(styleFor(_item(title: 'Task failed')).icon, Icons.error_rounded);
    });

    test('an end-to-end message is not read', () {
      final style = styleFor(_item(message: 'e2e1:ticket', isE2e: true));
      expect(style.icon, Icons.notifications_rounded);
    });
  });

  test('the fallback is the bell in slate', () {
    final style = styleFor(_item(title: 'Hello', message: 'Nothing special'));
    expect(style.icon, Icons.notifications_rounded);
    expect(style.tone, AppTones.slate);
  });

  test('colours follow the category', () {
    expect(styleFor(_item(category: 'reminders')).tone, AppTones.red);
    expect(styleFor(_item(title: 'Import completed')).tone, AppTones.green);
    expect(styleFor(_item(category: 'approvals')).tone, AppTones.orange);
    expect(styleFor(_item(actionType: 'tickets')).tone, AppTones.purple);
    expect(styleFor(_item(category: 'messages')).tone, AppTones.indigo);
  });

  test('every tone reads at 3:1 on its tint, and on white', () {
    for (final t in [
      AppTones.red,
      AppTones.green,
      AppTones.blue,
      AppTones.orange,
      AppTones.purple,
      AppTones.teal,
      AppTones.indigo,
      AppTones.slate,
    ]) {
      expect(_contrast(t.solid, t.tint), greaterThanOrEqualTo(3));
      expect(_contrast(t.solid, AppColors.background), greaterThanOrEqualTo(3));
    }
  });

  test('every tone has a strong shade readable on its tints', () {
    for (final tone in [
      AppTones.red,
      AppTones.green,
      AppTones.blue,
      AppTones.orange,
      AppTones.purple,
      AppTones.teal,
      AppTones.indigo,
      AppTones.slate,
    ]) {
      expect(_contrast(tone.solid, AppColors.background), greaterThan(4.5));
      expect(_contrast(tone.strong, tone.tint), greaterThan(4.5));
      expect(_contrast(tone.strong, tone.tintStrong), greaterThan(4.5));
    }
  });

  test('the category label comes from the rule, else General', () {
    expect(styleFor(_item(actionType: 'tickets')).category, 'Tickets');
    expect(styleFor(_item(title: 'Something odd')).category, 'General');
  });
}
