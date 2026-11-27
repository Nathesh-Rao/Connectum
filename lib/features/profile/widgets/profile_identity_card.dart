import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/inbox/inbox.dart';
import '../../../data/profile/presence.dart';
import 'presence_pill.dart';

/// The hero of the Profile: a large avatar in the soft ring of its picture's
/// colour, with the camera badge and the presence dot; the name, @username,
/// designation, enterprise and role chips; the presence pill and the status
/// line, which both open the status editor. Behind it a faint wash of the
/// picture's colour and the card's abstract corner shapes.
class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    super.key,
    required this.name,
    required this.username,
    required this.organisation,
    required this.presence,
    this.designation = '',
    this.roles = const [],
    this.status,
    this.picture,
    this.progress,
    this.onPhotoTap,
    this.onStatusTap,
    this.statusKey,
  });

  static const avatarSize = 96.0;
  static const _badge = 28.0;
  static const _badgeIcon = 16.0;
  static const _dot = 18.0;
  static const _ringWidth = 3.0;
  static const _scrimAlpha = 0.45;

  final String name;
  final String username;
  final String organisation;

  /// What the person shows: always drawn, offline or not.
  final Presence presence;
  final String designation;
  final List<String> roles;
  final String? status;
  final String? picture;

  /// 0 to 1 while a picture uploads; null when idle. A ring over the avatar.
  final double? progress;

  /// Taps the avatar (the photo sheet). Null while a picture is being sent.
  final VoidCallback? onPhotoTap;

  /// Taps the presence pill or the status line (the status editor).
  final VoidCallback? onStatusTap;

  /// Marks the presence pill and the status line (the first-run tour).
  final Key? statusKey;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.cardAll,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: AppColors.line),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: InboxAvatarWash(picture: picture)),
            const Positioned.fill(child: CardTopRightDecoration()),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Avatar(
                    name: name,
                    picture: picture,
                    presence: presence,
                    progress: progress,
                    onTap: onPhotoTap,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title,
                  ),
                  if (username.isNotEmpty)
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.readable.copyWith(color: AppColors.muted),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (designation.isNotEmpty)
                        _Chip(label: designation, isTonal: true),
                      if (organisation.isNotEmpty)
                        _Chip(
                          label: organisation,
                          icon: Icons.apartment_outlined,
                        ),
                      for (final role in roles) _Chip(label: role),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  KeyedSubtree(
                    key: statusKey,
                    child: Column(
                      children: [
                        PresencePill(presence: presence, onTap: onStatusTap),
                        StatusLine(status: status, onTap: onStatusTap),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.picture,
    required this.presence,
    required this.progress,
    required this.onTap,
  });

  final String name;
  final String? picture;
  final Presence presence;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Change profile photo',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: ProfileIdentityCard.avatarSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              InboxAvatarRing(
                name: name,
                picture: picture,
                dimension: ProfileIdentityCard.avatarSize,
              ),
              if (progress != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.ink.withValues(
                        alpha: ProfileIdentityCard._scrimAlpha,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator(
                        value: progress == 0 ? null : progress,
                        strokeWidth: ProfileIdentityCard._ringWidth,
                        color: AppColors.white,
                        backgroundColor: AppColors.white.withValues(
                          alpha: ProfileIdentityCard._scrimAlpha,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  width: ProfileIdentityCard._badge,
                  height: ProfileIdentityCard._badge,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                    border: Border.all(color: AppColors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.photo_camera,
                    size: ProfileIdentityCard._badgeIcon,
                    color: AppColors.white,
                  ),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  key: const ValueKey('profile-presence-dot'),
                  width: ProfileIdentityCard._dot,
                  height: ProfileIdentityCard._dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppPresenceTones.dot(presence),
                    border: Border.all(color: AppColors.white, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small rounded label that wraps its text, so a long designation or
/// enterprise name and a large text size stay inside the card.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.isTonal = false});

  final String label;
  final IconData? icon;
  final bool isTonal;

  @override
  Widget build(BuildContext context) {
    final ink = isTonal ? AppColors.primaryStrong : AppColors.noText;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.tagHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isTonal ? AppColors.primaryTint : AppColors.white,
          borderRadius: AppRadius.pillAll,
          border: isTonal ? null : Border.all(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: ink),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.readableStrong.copyWith(color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
