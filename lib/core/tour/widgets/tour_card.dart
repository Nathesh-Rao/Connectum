import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../tour_step.dart';
import '../tour_texts.dart';
import 'tour_gesture_hint.dart';

/// The white card of one tour step: icon, title, short text, an optional
/// gesture hint, progress dots, Skip and Next ("Got it" on the last step).
class TourCard extends StatelessWidget {
  const TourCard({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onSkip,
    this.isReduced = false,
  });

  static const double maxWidth = 320;
  static const double iconCircle = 40;

  final TourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isReduced;

  bool get _isLast => index == total - 1;

  @override
  Widget build(BuildContext context) {
    final tone = step.tone;
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.sheet)),
              boxShadow: AppShadows.card,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: iconCircle,
                        height: iconCircle,
                        decoration: BoxDecoration(
                          color: tone.tint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(step.icon, size: 20, color: tone.strong),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(step.title, style: AppText.subtitle),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              step.body,
                              style: AppText.body.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                            if (step.gesture != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              TourGestureHint(
                                gesture: step.gesture!,
                                tone: tone,
                                isReduced: isReduced,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          label: TourTexts.progress(index, total),
                          excludeSemantics: true,
                          child: Wrap(
                            spacing: AppSpacing.xxs,
                            runSpacing: AppSpacing.xxs,
                            children: [
                              for (var i = 0; i < total; i++)
                                _Dot(isActive: i == index, tone: tone),
                            ],
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: TourTexts.skipLabel,
                        excludeSemantics: true,
                        child: AppButton.text(
                          label: TourTexts.skip,
                          onPressed: onSkip,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _NextPill(
                        label: _isLast ? TourTexts.done : TourTexts.next,
                        semanticLabel: _isLast
                            ? TourTexts.doneLabel
                            : TourTexts.nextLabel,
                        tone: tone,
                        onPressed: onNext,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.isActive, required this.tone});

  final bool isActive;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      width: isActive ? 16 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: isActive ? tone.solid : tone.tintStrong,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      ),
    );
  }
}

class _NextPill extends StatelessWidget {
  const _NextPill({
    required this.label,
    required this.semanticLabel,
    required this.tone,
    required this.onPressed,
  });

  final String label;
  final String semanticLabel;
  final AppTone tone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tone.strong,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadius.pill),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppText.button.copyWith(color: AppColors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
