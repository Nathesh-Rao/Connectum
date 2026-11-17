import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_avatar.dart';

/// The profile control of a top bar: the person's picture, or the first letter
/// on a coloured circle while there is none (and while it loads), the height
/// of the notification bell's circle, in one tap area of at least 48 dp.
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
          child: Center(
            child: AppAvatar(
              name: name,
              kind: AppAvatarKind.person,
              picture: picture,
              size: AppSpacing.bellCircle,
            ),
          ),
        ),
      ),
    );
  }
}
