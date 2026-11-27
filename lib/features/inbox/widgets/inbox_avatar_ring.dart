import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';

/// The person's face on an Inbox card: a solid ring in a colour taken from the
/// picture (the initials colour without a picture or while it is read, then it
/// animates to the read colour), a surface gap, then the photo.
class InboxAvatarRing extends StatelessWidget {
  const InboxAvatarRing({
    super.key,
    required this.name,
    this.picture,
    this.dimension = size,
  });

  final String name;
  final String? picture;

  /// The outer size; the Inbox card's by default.
  final double dimension;

  static const size = AppSpacing.inboxRingSize;
  static const stroke = AppSpacing.inboxRingStroke;
  static const gap = AppSpacing.inboxRingGap;
  static const photoSize = size - 2 * (stroke + gap);

  @override
  Widget build(BuildContext context) {
    if (AvatarTint.isKnown(picture)) return _ring(AvatarTint.peek(picture));
    return FutureBuilder<Color?>(
      future: AvatarTint.of(picture),
      builder: (context, snapshot) => _ring(snapshot.data),
    );
  }

  Widget _ring(Color? color) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: color ?? AppColors.avatarText),
    duration: AppDurations.slow,
    curve: AppCurves.out,
    builder: (context, ring, child) => Container(
      key: const ValueKey('inbox-avatar-ring'),
      width: dimension,
      height: dimension,
      padding: const EdgeInsets.all(gap),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.white,
        border: Border.all(color: ring ?? AppColors.avatarText, width: stroke),
      ),
      child: child,
    ),
    child: AppAvatar(
      name: name,
      size: dimension - 2 * (stroke + gap),
      picture: picture,
    ),
  );
}
