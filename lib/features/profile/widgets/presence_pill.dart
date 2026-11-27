import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../../../data/profile/presence.dart';
import '../profile_texts.dart';

/// A coloured dot, as on an avatar corner.
class PresenceDotView extends StatelessWidget {
  const PresenceDotView({super.key, required this.presence, this.size = 10});

  final Presence presence;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppPresenceTones.dot(presence),
    ),
  );
}

/// The dot and the label of a presence in a tonal pill. With [onTap] the hit
/// area is at least 44 high.
class PresencePill extends StatelessWidget {
  const PresencePill({super.key, required this.presence, this.onTap});

  final Presence presence;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = AppPresenceTones.of(presence);
    final pill = Container(
      constraints: const BoxConstraints(
        minHeight: AppSpacing.compactPillHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PresenceDotView(presence: presence),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              presence.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.readableStrong.copyWith(color: tone.strong),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: 'Presence: ${presence.label}. Change your status',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// The status message under the name; muted "Add a status" when there is none.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.status, this.onTap});

  final String? status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasStatus = status != null && status!.trim().isNotEmpty;
    final text = Text(
      hasStatus ? status! : ProfileTexts.addStatus,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: AppText.readable.copyWith(
        color: hasStatus ? AppColors.ink : AppColors.muted,
      ),
    );
    return Semantics(
      button: onTap != null,
      label: hasStatus ? 'Status: $status. Edit' : ProfileTexts.addStatus,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Center(child: text),
          ),
        ),
      ),
    );
  }
}
