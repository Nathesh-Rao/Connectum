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
    this.trailing = const [],
  });

  final String title;
  final String? status;
  final bool isSquareAvatar;
  final AppPresenceDot presence;
  final VoidCallback onBack;
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
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong,
                ),
                if (status != null)
                  Text(
                    status!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
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
