import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

enum AppPresenceDot { none, online, offline }

/// Initials on a neutral tint. Circle for a person, rounded square for a
/// group or team. An optional presence dot sits on the bottom right.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = AppSpacing.avatar,
    this.isSquare = false,
    this.isAccent = false,
    this.presence = AppPresenceDot.none,
  });

  final String name;
  final double size;
  final bool isSquare;

  /// White initials on the accent colour, in the larger title size (profile).
  final bool isAccent;
  final AppPresenceDot presence;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (p) =>
              p.isNotEmpty &&
              RegExp(r'^[\p{L}\p{N}]', unicode: true).hasMatch(p),
        );
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isSquare
            ? const BorderRadius.all(Radius.circular(AppRadius.control))
            : null,
        color: isAccent ? AppColors.accent : AppColors.avatarBg,
      ),
      child: Text(
        _initials,
        style: isAccent
            ? AppText.title.copyWith(color: AppColors.background)
            : AppText.readableStrong.copyWith(color: AppColors.avatarText),
      ),
    );
    if (presence == AppPresenceDot.none) return avatar;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: AppSpacing.presenceDot,
              height: AppSpacing.presenceDot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: presence == AppPresenceDot.online
                    ? AppColors.yesDot
                    : AppColors.noDot,
                border: Border.all(color: AppColors.background, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
