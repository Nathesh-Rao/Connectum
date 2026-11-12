import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';

class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.name,
    required this.username,
    required this.organisation,
    required this.isOnline,
  });

  static const _avatarSize = 72.0;

  final String name;
  final String username;
  final String organisation;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          AppAvatar(
            name: name,
            size: _avatarSize,
            isAccent: true,
            presence: isOnline ? AppPresenceDot.online : AppPresenceDot.offline,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle,
                ),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.readable.copyWith(color: AppColors.muted),
                  ),
                if (organisation.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      const Icon(
                        Icons.apartment_outlined,
                        size: 16,
                        color: AppColors.primaryStrong,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: Text(
                          organisation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.readableStrong,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
