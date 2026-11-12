import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/avatar_palette.dart';
import '../../core/widgets/app_ambient_backdrop.dart';
import '../../core/widgets/app_card_circles.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_success_animation.dart';
import 'debug_decor_controller.dart';

/// Debug only: every decorative element of the onboarding, auth and state
/// screens, with the tokens it is made of and the contrast of text over it.
class DebugDecorView extends GetView<DebugDecorController> {
  const DebugDecorView({super.key});

  static const _elements = <(String, String, List<(String, Color)>)>[
    (
      'Onboarding band (OnboardingStage)',
      'onboarding_stage.dart',
      [
        ('primaryBorder 55 %', AppColors.primaryBorder),
        ('primaryTintStrong 95 %', AppColors.primaryTintStrong),
        ('white', AppColors.white),
        ('sphere glow: primaryBorder 45 %', AppColors.primaryBorder),
      ],
    ),
    (
      'Ambient backdrop (splash, auth, verification)',
      'app_ambient_backdrop.dart',
      [
        ('ambientDiscCenter / Edge', AppColors.ambientDiscCenter),
        ('ambientOrbitOuter', AppColors.ambientOrbitOuter),
        ('ambientOrbitInner', AppColors.ambientOrbitInner),
        ('sphereHighlight', AppColors.sphereHighlight),
        ('sphereMid', AppColors.sphereMid),
        ('primaryBright', AppColors.primaryBright),
      ],
    ),
    (
      'Progress dots (onboarding)',
      'onboarding_view.dart',
      [
        ('active: primaryBright', AppColors.primaryBright),
        ('inactive: inputBorder', AppColors.inputBorder),
      ],
    ),
    (
      'Animations (Lottie, recoloured copies)',
      'tool/lottie/recolor_lottie.py',
      [
        ('primaryBright', AppColors.primaryBright),
        ('primaryLight', AppColors.primaryLight),
        ('primaryBorder', AppColors.primaryBorder),
        ('primaryTintStrong', AppColors.primaryTintStrong),
        ('primaryTint', AppColors.primaryTint),
        ('white', AppColors.white),
        ('violet (agents robot eyes)', AppColors.violet),
      ],
    ),
  ];

  static const _overText = <(String, Color, Color)>[
    ('ink on white', AppColors.ink, AppColors.white),
    ('muted on white', AppColors.muted, AppColors.white),
    ('ink on primaryTint', AppColors.ink, AppColors.primaryTint),
    (
      'muted on primaryTintStrong',
      AppColors.muted,
      AppColors.primaryTintStrong,
    ),
    ('primary on white', AppColors.primary, AppColors.white),
    ('white on primary', AppColors.white, AppColors.primary),
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          const Text('Decor', style: AppText.display),
          for (final e in _elements) ...[
            _section(e.$1),
            Text(e.$2, style: AppText.caption.copyWith(color: AppColors.muted)),
            const SizedBox(height: AppSpacing.xxs),
            for (final t in e.$3) _Swatch(t.$1, t.$2),
          ],
          _section('Ambient: splash and access'),
          const Row(
            children: [
              Expanded(child: _Frame(AppAmbientVariant.splash)),
              SizedBox(width: AppSpacing.xs),
              Expanded(child: _Frame(AppAmbientVariant.access)),
            ],
          ),
          _section('Card circles'),
          const SizedBox(
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: AppRadius.mdAll,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.line),
                ),
              ),
              child: ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: AppCardCircles(child: SizedBox.expand()),
              ),
            ),
          ),
          _section('Success check'),
          const Center(child: AppSuccessAnimation()),
          _section('Text over decoration (contrast, needs 4.5)'),
          for (final o in _overText) _Contrast(o.$1, o.$2, o.$3),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  static Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xxs),
    child: Text(title, style: AppText.subtitle),
  );
}

class _Frame extends StatelessWidget {
  const _Frame(this.variant);

  final AppAmbientVariant variant;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.55,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.line),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.mdAll,
          child: AppAmbientBackdrop(variant: variant),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: AppColors.line),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(name, style: AppText.readable)),
        ],
      ),
    );
  }
}

class _Contrast extends StatelessWidget {
  const _Contrast(this.label, this.ink, this.background);

  final String label;
  final Color ink;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final ratio = AvatarPalette.contrast(ink, background);
    final isOk = ratio >= 4.5;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        '$label  ${ratio.toStringAsFixed(1)}:1  ${isOk ? 'ok' : 'LOW'}',
        style: AppText.readableStrong.copyWith(color: ink),
      ),
    );
  }
}
