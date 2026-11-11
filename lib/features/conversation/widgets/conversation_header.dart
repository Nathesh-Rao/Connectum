import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';

/// Back, avatar, title and a status line; the avatar and the two lines open
/// the chat info. Whatever is added on the right
/// later (the prototype has a sparkle button and a menu) goes in [trailing]
/// and never moves the title.
class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.title,
    required this.status,
    required this.avatar,
    required this.onBack,
    this.isEncrypted = false,
    this.onInfoTap,
    this.trailing = const [],
  });

  final String title;
  final String? status;

  /// Built by [conversationAvatarFor], so it matches the chat list.
  final Widget avatar;
  final bool isEncrypted;
  final VoidCallback onBack;
  final VoidCallback? onInfoTap;
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
          Expanded(
            child: Semantics(
              button: onInfoTap != null,
              label: 'Chat info, $title',
              excludeSemantics: onInfoTap != null,
              child: InkWell(
                onTap: onInfoTap,
                borderRadius: AppRadius.controlAll,
                child: Row(
                  children: [
                    avatar,
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
                            Text(
                              status!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
