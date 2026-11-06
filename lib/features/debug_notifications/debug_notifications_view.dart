import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_popup_menu.dart';
import '../notifications/models/feed_item.dart';
import '../notifications/notification_style.dart';
import '../notifications/widgets/feed_detail_sheet.dart';
import '../notifications/widgets/feed_tile.dart';
import '../notifications/widgets/notifications_more_menu.dart';
import 'debug_notifications_controller.dart';

const _longText =
    'A very long title that keeps going well past two lines so the ellipsis '
    'shows on a narrow phone';
const _longBody =
    'A very long body that keeps going well past three lines. It repeats: '
    'the quick brown fox jumps over the lazy dog, again and again, so the '
    'row has to clip it instead of growing without end.';

FeedItem _sample(
  String id,
  String title,
  String message, {
  String priority = 'low',
  bool isRead = false,
  String? category,
  String? actionType,
  String? icon,
  int count = 1,
}) => FeedItem(
  id: id,
  title: title,
  message: message,
  priority: priority,
  isRead: isRead,
  category: category,
  actionType: actionType,
  icon: icon,
  count: count,
  ts: DateTime.now().millisecondsSinceEpoch - 5 * 60 * 1000,
);

/// One item for every rule of the mapper, every priority, read and unread, and
/// long text.
final _samples = [
  _sample('s1', 'Ana', 'Ana: lunch at one?', category: 'messages'),
  _sample('s2', 'Mention', 'Sam mentioned you', icon: 'alternate_email'),
  _sample('s3', 'Approval needed', 'Leave request', category: 'approvals'),
  _sample('s4', 'Task assigned', 'Review the plan', icon: 'task_alt'),
  _sample('s5', 'Ticket TK-12', 'Status changed', actionType: 'tickets'),
  _sample('s6', 'Submission', 'Form 7 was submitted'),
  _sample('s7', 'Reminder', 'Closing date is tomorrow', category: 'reminders'),
  _sample('s8', 'New device', 'A device was added', category: 'security'),
  _sample('s9', 'Announcement', 'Office closed on Friday'),
  _sample('s10', 'Upload done', 'Recording uploaded'),
  _sample('s11', 'Invite', 'Priya joined your team'),
  _sample('s12', 'Completed', 'Import completed'),
  _sample('s13', 'Failed', 'Import failed'),
  _sample('s14', 'System', 'Maintenance', category: 'system'),
  _sample('s15', 'Something', 'No rule matches'),
  _sample('p1', 'High, unread', 'Priority high', priority: 'high'),
  _sample(
    'p2',
    'Medium, read',
    'Priority medium',
    priority: 'medium',
    isRead: true,
  ),
  _sample('p3', 'Low', 'Priority low, no pill', priority: 'low'),
  _sample(
    'p4',
    'Resolved',
    'Priority resolved',
    priority: 'resolved',
    isRead: true,
  ),
  _sample('l1', _longText, _longBody, priority: 'high', count: 120),
];

/// The first sample of every category of the mapper.
final _categorySamples = () {
  final seen = <String>{};
  return [
    for (final item in _samples)
      if (seen.add(styleFor(item).category)) item,
  ];
}();

class DebugNotificationsView extends GetView<DebugNotificationsController> {
  const DebugNotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget gap() => const SizedBox(height: AppSpacing.xs);
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          const Text('Notification test hooks', style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Events go straight into the feed, as if the server sent them, and '
            'become system notifications by the same rules as live ones. '
            '"Fire a local notification" posts one whatever the rules say.',
            style: AppText.readable,
          ),
          AppButton.secondary(
            label: 'Plain message',
            onPressed: c.plainMessage,
          ),
          gap(),
          AppButton.secondary(label: 'Mention', onPressed: c.mention),
          gap(),
          AppButton.secondary(
            label: 'Group message (low)',
            onPressed: c.groupMessage,
          ),
          gap(),
          AppButton.secondary(label: 'Approval', onPressed: c.approval),
          gap(),
          AppButton.secondary(label: 'Task', onPressed: c.task),
          gap(),
          AppButton.secondary(label: 'E2E envelope', onPressed: c.e2eEnvelope),
          gap(),
          AppButton.secondary(
            label: 'Coalesced (tap three times)',
            onPressed: c.coalesced,
          ),
          gap(),
          AppButton.secondary(label: 'Read last', onPressed: c.readLast),
          gap(),
          AppButton.secondary(label: 'Resolve last', onPressed: c.resolveLast),
          gap(),
          AppButton.secondary(label: 'Remove last', onPressed: c.removeLast),
          gap(),
          AppButton.primary(
            label: 'Fire a local notification',
            onPressed: c.fireLocal,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Expanded(
                child: Text('Tiles and the more menu', style: AppText.title),
              ),
              NotificationsMoreMenu(
                shouldNotifyGroups: true.obs,
                isUnreadOnly: false.obs,
                onSelected: (_) {},
              ),
            ],
          ),
          const Text('Popup menu states', style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _DebugMenuPreview(isGroups: true, isUnread: false),
              _DebugMenuPreview(isGroups: false, isUnread: true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Per category: swipe and sheet header',
            style: AppText.title,
          ),
          for (final item in _categorySamples) ...[
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: AppSpacing.feedIconCircle,
              child: FeedSwipeBackground(style: styleFor(item)),
            ),
            const SizedBox(height: AppSpacing.xs),
            FeedSheetHeader(item: item),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final item in _samples)
            FeedTile(
              item: item,
              readText: (i) => Future.value(i.message),
              onTap: () {},
              onMenu: (_) {},
              onDismissed: () {},
            ),
        ],
      ),
    );
  }
}

/// The open state of the popup card, in place, with a disabled row.
class _DebugMenuPreview extends StatelessWidget {
  const _DebugMenuPreview({required this.isGroups, required this.isUnread});

  final bool isGroups;
  final bool isUnread;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppSpacing.popupMenuMaxWidth,
    child: AppPopupMenuCard(
      items: [
        AppMenuItem(
          icon: Icons.notifications_active_rounded,
          label: 'Notify for group messages',
          switchValue: isGroups.obs,
          onTap: () {},
        ),
        AppMenuItem(
          icon: Icons.mark_email_unread_rounded,
          label: 'Unread only',
          switchValue: isUnread.obs,
          onTap: () {},
        ),
        AppMenuItem(
          icon: Icons.done_all_rounded,
          label: 'Mark all read',
          hasDividerBefore: true,
          onTap: () {},
        ),
        AppMenuItem(
          icon: Icons.task_alt_rounded,
          label: 'Mark all resolved (disabled)',
          isEnabled: false,
          onTap: () {},
        ),
        AppMenuItem(
          icon: Icons.delete_sweep_rounded,
          label: 'Clear resolved',
          isDanger: true,
          onTap: () {},
        ),
      ],
    ),
  );
}
