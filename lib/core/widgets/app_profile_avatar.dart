import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'app_avatar.dart';

/// The profile control of a top bar: the person's picture, or the first letter
/// on a coloured circle while there is none (and while it loads), on a violet ring (38 dp, the bell pill's height), in one tap area of at least 48 dp.
class AppProfileAvatar extends StatelessWidget {
  const AppProfileAvatar({
    super.key,
    required this.name,
    required this.onPressed,
    this.picture,
  });

  final String name;
  final String? picture;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Profile',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppSpacing.badgedIconHit,
            minHeight: AppSpacing.badgedIconHit,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Container(
                width: AppSpacing.profileAvatar,
                height: AppSpacing.profileAvatar,
                padding: const EdgeInsets.all(AppSpacing.profileRingGap),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.violetRing,
                    width: AppSpacing.profileRing,
                  ),
                ),
                child: AppAvatar(
                  name: name,
                  kind: AppAvatarKind.person,
                  picture: picture,
                  size:
                      AppSpacing.profileAvatar -
                      2 * (AppSpacing.profileRing + AppSpacing.profileRingGap),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
