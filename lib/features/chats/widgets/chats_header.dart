import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_notification_bell.dart';

/// The Chats app bar: the enterprise title on the left, the notification bell
/// on the right.
class ChatsHeader extends StatelessWidget {
  const ChatsHeader({
    super.key,
    required this.enterpriseName,
    required this.unread,
    required this.onSwitchEnterprise,
    required this.onOpenNotifications,
  });

  /// Read inside an Obx, so it may read observables.
  final String Function() enterpriseName;
  final int Function() unread;
  final VoidCallback onSwitchEnterprise;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
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
          Obx(
            () => AppNotificationBell(
              count: unread(),
              onPressed: onOpenNotifications,
            ),
          ),
        ],
      ),
    );
  }
}
