import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/reaction.dart';

/// The quick reaction row at the top of the long-press sheet: the six common
/// emoji and a "+" that opens ten more under them. The ones I already used
/// are filled.
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({
    super.key,
    required this.mine,
    required this.isEnabled,
    required this.onPick,
  });

  final Set<String> mine;
  final bool isEnabled;
  final void Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    final isOpen = false.obs;
    return Opacity(
      opacity: isEnabled ? 1 : 0.45,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final e in Reaction.quick)
                _Emoji(
                  emoji: e,
                  isMine: mine.contains(e),
                  onTap: () => onPick(e),
                ),
              Obx(
                () => _Cell(
                  isMine: false,
                  onTap: () => isOpen.toggle(),
                  label: isOpen.value ? 'Fewer reactions' : 'More reactions',
                  child: AnimatedRotation(
                    turns: isOpen.value ? 0.125 : 0,
                    duration: AppDurations.fast,
                    curve: AppCurves.out,
                    child: const Icon(
                      Icons.add,
                      size: 22,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Obx(
            () => AnimatedSize(
              duration: AppDurations.base,
              curve: AppCurves.out,
              alignment: Alignment.topCenter,
              child: isOpen.value
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Wrap(
                        spacing: AppSpacing.xxs,
                        runSpacing: AppSpacing.xxs,
                        children: [
                          for (final e in Reaction.more)
                            _Emoji(
                              emoji: e,
                              isMine: mine.contains(e),
                              onTap: () => onPick(e),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

class _Emoji extends StatelessWidget {
  const _Emoji({
    required this.emoji,
    required this.isMine,
    required this.onTap,
  });

  final String emoji;
  final bool isMine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Cell(
    isMine: isMine,
    onTap: onTap,
    label: emoji,
    child: Text(emoji, style: const TextStyle(fontSize: 22, height: 1.2)),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.isMine,
    required this.onTap,
    required this.label,
    required this.child,
  });

  final bool isMine;
  final VoidCallback onTap;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isMine,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.out,
        width: AppSpacing.minTapTarget,
        height: AppSpacing.minTapTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isMine ? AppColors.primaryTint : Colors.transparent,
          borderRadius: AppRadius.pillAll,
        ),
        child: child,
      ),
    ),
  );
}
