import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_popup_menu.dart';
import '../notification_texts.dart';

enum NotificationsMenuItem {
  notifyGroups,
  unreadOnly,
  markAllRead,
  markAllResolved,
  clearResolved,
}

/// The three-dot menu of the Notifications screen: the two switches, then the
/// bulk actions.
class NotificationsMoreMenu extends StatelessWidget {
  const NotificationsMoreMenu({
    super.key,
    required this.shouldNotifyGroups,
    required this.isUnreadOnly,
    required this.onSelected,
  });

  final RxBool shouldNotifyGroups;
  final RxBool isUnreadOnly;
  final ValueChanged<NotificationsMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppPopupMenu(
      tooltip: NotificationTexts.menu,
      items: [
        AppMenuItem(
          icon: Icons.notifications_active_rounded,
          label: NotificationTexts.notifyGroups,
          switchValue: shouldNotifyGroups,
          onTap: () => onSelected(NotificationsMenuItem.notifyGroups),
        ),
        AppMenuItem(
          icon: Icons.mark_email_unread_rounded,
          label: NotificationTexts.unreadOnly,
          switchValue: isUnreadOnly,
          onTap: () => onSelected(NotificationsMenuItem.unreadOnly),
        ),
        AppMenuItem(
          icon: Icons.done_all_rounded,
          label: NotificationTexts.markAllRead,
          hasDividerBefore: true,
          onTap: () => onSelected(NotificationsMenuItem.markAllRead),
        ),
        AppMenuItem(
          icon: Icons.task_alt_rounded,
          label: NotificationTexts.markAllResolved,
          onTap: () => onSelected(NotificationsMenuItem.markAllResolved),
        ),
        AppMenuItem(
          icon: Icons.delete_sweep_rounded,
          label: NotificationTexts.clearResolved,
          isDanger: true,
          onTap: () => onSelected(NotificationsMenuItem.clearResolved),
        ),
      ],
    );
  }
}
