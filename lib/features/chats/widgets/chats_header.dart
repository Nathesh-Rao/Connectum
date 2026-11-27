import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_notification_bell.dart';
import '../../../core/widgets/app_profile_avatar.dart';

/// The Chats app bar: the enterprise title on the left, the notification bell
/// and the profile avatar on the right.
class ChatsHeader extends StatelessWidget {
  const ChatsHeader({
    super.key,
    required this.enterpriseName,
    required this.unread,
    required this.onSwitchEnterprise,
    required this.onOpenNotifications,
    required this.profileName,
    required this.profilePicture,
    required this.onOpenProfile,
    this.switcherKey,
    this.actionsKey,
  });

  /// Read inside an Obx, so it may read observables.
  final String Function() enterpriseName;
  final int Function() unread;
  final VoidCallback onSwitchEnterprise;
  final VoidCallback onOpenNotifications;

  /// Read inside an Obx, so they may read observables.
  final String Function() profileName;
  final String? Function() profilePicture;
  final VoidCallback onOpenProfile;

  /// Targets of the first-run tour: the enterprise switcher, and the bell with
  /// the profile picture.
  final GlobalKey? switcherKey;
  final GlobalKey? actionsKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.headerHeight,
      padding: const EdgeInsets.only(
        left: AppSpacing.page,
        right: AppSpacing.profileEdge,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: KeyedSubtree(
                key: switcherKey,
                child: Semantics(
                  button: true,
                  label: 'Switch enterprise',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSwitchEnterprise,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AppSpacing.minTapTarget,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('YOUR ENTERPRISE', style: AppText.eyebrow),
                          Obx(
                            () => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    enterpriseName(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.subtitle,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 18,
                                  color: AppColors.ink,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          KeyedSubtree(
            key: actionsKey,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => AppNotificationBell(
                    count: unread(),
                    onPressed: onOpenNotifications,
                  ),
                ),
                const SizedBox(width: AppSpacing.bellAvatarGap),
                Obx(
                  () => AppProfileAvatar(
                    name: profileName(),
                    picture: profilePicture(),
                    onPressed: onOpenProfile,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
