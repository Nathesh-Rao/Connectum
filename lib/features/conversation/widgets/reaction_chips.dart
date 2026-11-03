import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../data/models/reaction.dart';

/// The reactions under a bubble or a card: an emoji and its count, muted,
/// with an accent outline when I reacted. A tap toggles my reaction. A chip
/// pops when its count changes or when it first appears.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.reactions,
    required this.onToggle,
  });

  final List<Reaction> reactions;
  final void Function(String emoji) onToggle;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Wrap(
        spacing: AppSpacing.xxs,
        runSpacing: AppSpacing.xxs,
        children: [
          for (final r in reactions)
            _Chip(reaction: r, onTap: () => onToggle(r.emoji)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.reaction, required this.onTap});

  final Reaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reaction;
    final chip = Semantics(
      button: true,
      selected: r.isMine,
      label: '${r.emoji} ${r.count}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppCurves.out,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs / 2,
          ),
          decoration: BoxDecoration(
            color: r.isMine ? AppColors.accentSoft : AppColors.bubbleIn,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: r.isMine ? AppColors.accent : AppColors.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.emoji, style: AppText.readable),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                '${r.count}',
                style: AppText.caption.copyWith(
                  color: r.isMine ? AppColors.accentInk : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return chip;
    return TweenAnimationBuilder<double>(
      key: ValueKey('${r.emoji}|${r.count}'),
      tween: Tween<double>(begin: AppDistances.chipPopScale, end: 1),
      duration: AppDurations.base,
      curve: Curves.easeOutBack,
      child: chip,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
    );
  }
}
