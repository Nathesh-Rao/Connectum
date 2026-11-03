import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';

/// Back, avatar, title and a status line. Whatever is added on the right
/// later (the prototype has a sparkle button and a menu) goes in [trailing]
/// and never moves the title.
class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.title,
    required this.status,
    required this.isSquareAvatar,
    required this.onBack,
    this.presence = AppPresenceDot.none,
    this.isEncrypted = false,
    this.onStatusTap,
    this.trailing = const [],
  });

  final String title;
  final String? status;
  final bool isSquareAvatar;
  final AppPresenceDot presence;
  final bool isEncrypted;
  final VoidCallback onBack;
  final VoidCallback? onStatusTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.conversationHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          AppButton.icon(
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: onBack,
          ),
          AppAvatar(name: title, isSquare: isSquareAvatar, presence: presence),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong,
                      ),
                    ),
                    if (isEncrypted) ...[
                      const SizedBox(width: AppSpacing.xxs),
                      const Icon(
                        Icons.lock,
                        size: AppSpacing.statusIcon,
                        color: AppColors.yesText,
                        semanticLabel: 'End-to-end encrypted',
                      ),
                    ],
                  ],
                ),
                if (status != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onStatusTap,
                    child: Text(
                      status!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ),
              ],
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
