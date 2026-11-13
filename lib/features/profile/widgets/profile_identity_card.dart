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
    this.picture,
    this.progress,
    this.onPhotoTap,
  });

  static const _avatarSize = 72.0;

  final String name;
  final String username;
  final String organisation;
  final bool isOnline;
  final String? picture;

  /// 0 to 1 while a picture uploads; null when idle. A ring over the avatar.
  final double? progress;

  /// Taps the avatar (the photo sheet). Null while a picture is being sent.
  final VoidCallback? onPhotoTap;

  static const _badge = 24.0;
  static const _badgeIcon = 14.0;
  static const _ringWidth = 3.0;
  static const _scrimAlpha = 0.45;

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
          GestureDetector(
            onTap: onPhotoTap,
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              label: 'Change profile photo',
              child: SizedBox.square(
                dimension: _avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppAvatar(
                      name: name,
                      size: _avatarSize,
                      isAccent: true,
                      picture: picture,
                      presence: isOnline
                          ? AppPresenceDot.online
                          : AppPresenceDot.offline,
                    ),
                    if (progress != null)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.ink.withValues(alpha: _scrimAlpha),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: CircularProgressIndicator(
                              value: progress == 0 ? null : progress,
                              strokeWidth: _ringWidth,
                              color: AppColors.white,
                              backgroundColor: AppColors.white.withValues(
                                alpha: _scrimAlpha,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: -AppSpacing.xxs,
                      bottom: -AppSpacing.xxs,
                      child: Container(
                        width: _badge,
                        height: _badge,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          border: Border.all(color: AppColors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.photo_camera,
                          size: _badgeIcon,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
