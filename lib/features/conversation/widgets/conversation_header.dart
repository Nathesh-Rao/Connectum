import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';

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
    this.onAvatarTap,
    this.trailing = const [],
  });

  final String title;
  final String? status;

  /// Built by [conversationAvatarFor], so it matches the chat list.
  final Widget avatar;
  final bool isEncrypted;
  final VoidCallback onBack;
  final VoidCallback? onInfoTap;

  /// Opens the person's profile (a direct chat); the avatar then has its own
  /// 44 pt hit area. Null leaves the avatar part of the info tap.
  final VoidCallback? onAvatarTap;
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
                    if (onAvatarTap == null)
                      avatar
                    else
                      Semantics(
                        button: true,
                        label: 'Profile, $title',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onAvatarTap,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: AppSpacing.minTapTarget,
                              minHeight: AppSpacing.minTapTarget,
                            ),
                            child: Center(child: avatar),
                          ),
                        ),
                      ),
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
                                  style: AppText.chatHeaderName,
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
                              style: AppText.chatStatus,
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
