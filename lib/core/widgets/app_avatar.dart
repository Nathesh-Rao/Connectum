import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../theme/app_motion.dart';
import '../utils/avatar_palette.dart';
import 'app_png_icon.dart';
import 'avatar_image.dart';

enum AppPresenceDot { none, online, offline }

/// What an avatar stands for. A person is a circle with a picture or the first
/// letter; a group and a ticket are rounded squares with an icon.
enum AppAvatarKind { person, group, ticket }

/// Without a [kind]: initials on a neutral tint, a circle for a person, a
/// rounded square for a group or team. With a [kind]: the colours come from
/// [AvatarPalette] for the name. An optional presence dot sits on the bottom
/// right.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = AppSpacing.avatar,
    this.kind,
    this.image,
    this.picture,
    this.isSquare = false,
    this.isAccent = false,
    this.presence = AppPresenceDot.none,
  });

  final String name;
  final double size;
  final AppAvatarKind? kind;

  /// A person's picture, drawn instead of the letter when given.
  final ImageProvider? image;

  /// The person's picture address (`/uploads/..`, `asset:..`, `memory:..`),
  /// drawn over the initials. While it loads, when it fails and when it is
  /// null the initials and the colour from the name show, unchanged. Only a
  /// person (a circle) or a plain avatar takes it; a group and a ticket keep
  /// their icon.
  final String? picture;
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

  static const _iconRatio = 0.5;
  static const _letterRatio = 0.4;

  String get _letter {
    final runes = name.trim().runes.toList();
    if (runes.isEmpty) return '?';
    final letter = runes.firstWhere(
      (r) => RegExp(
        r'^[\p{L}\p{N}]',
        unicode: true,
      ).hasMatch(String.fromCharCode(r)),
      orElse: () => runes.first,
    );
    return String.fromCharCode(letter).toUpperCase();
  }

  Widget _kindAvatar(AppAvatarKind kind) {
    final colors = AvatarPalette.fromName(name);
    if (kind == AppAvatarKind.person) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.background,
          image: image == null
              ? null
              : DecorationImage(image: image!, fit: BoxFit.cover),
        ),
        child: image != null
            ? null
            : Text(
                _letter,
                style: AppText.readableStrong.copyWith(
                  color: colors.foreground,
                  fontSize: size * _letterRatio,
                  height: 1,
                ),
              ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(
          Radius.circular(AppRadius.control),
        ),
        color: colors.background,
      ),
      child: AppPngIcon(
        asset: kind == AppAvatarKind.ticket
            ? AppIcons.home.ticket
            : AppIcons.home.group,
        size: size * _iconRatio,
        color: colors.foreground,
      ),
    );
  }

  Widget _withPicture(Widget base) {
    final provider = kind == null || kind == AppAvatarKind.person
        ? AvatarImages.providerFor(picture)
        : null;
    if (provider == null) return base;
    final isRound = kind != null || !isSquare;
    final photo = Image(
      image: provider,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, isSync) => AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: isSync ? Duration.zero : AppDurations.fast,
        child: child,
      ),
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    );
    return Stack(
      children: [
        base,
        Positioned.fill(
          child: isRound
              ? ClipOval(child: photo)
              : ClipRRect(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadius.control),
                  ),
                  child: photo,
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = this.kind;
    final avatar = kind != null
        ? _kindAvatar(kind)
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: isSquare
                  ? const BorderRadius.all(Radius.circular(AppRadius.control))
                  : null,
              color: isAccent ? AppColors.primary : AppColors.avatarBg,
            ),
            child: Text(
              _initials,
              style: isAccent
                  ? AppText.title.copyWith(color: AppColors.white)
                  : AppText.readableStrong.copyWith(
                      color: AppColors.avatarText,
                    ),
            ),
          );
    final shown = _withPicture(avatar);
    if (presence == AppPresenceDot.none) return shown;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          shown,
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
                border: Border.all(color: AppColors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
