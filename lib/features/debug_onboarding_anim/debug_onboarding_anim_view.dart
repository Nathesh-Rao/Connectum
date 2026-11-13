import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/onboarding_art/onboarding_art.dart';
import '../../core/widgets/onboarding_art/onboarding_art_palette.dart';
import 'debug_onboarding_anim_controller.dart';

/// Debug only: the three onboarding animations on a plain page with play,
/// pause, replay, a time slider, speed, the colour switch and a backdrop.
class DebugOnboardingAnimView extends GetView<DebugOnboardingAnimController> {
  const DebugOnboardingAnimView({super.key});

  static const _titles = {
    OnboardingArtKind.network: 'Network (conversations)',
    OnboardingArtKind.buildings: 'Buildings (enterprises)',
    OnboardingArtKind.shield: 'Shield (security)',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          const Text('Onboarding animations', style: AppText.display),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Obx(
                  () => AppButton.secondary(
                    label: c.isPlaying.value ? 'Pause' : 'Play',
                    onPressed: c.togglePlay,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Replay',
                  onPressed: c.replay,
                ),
              ),
            ],
          ),
          ValueListenableBuilder<double>(
            valueListenable: c.clock.time,
            builder: (context, t, _) => Row(
              children: [
                Expanded(
                  child: Slider(
                    value: t.clamp(0, DebugOnboardingAnimController.maxTime),
                    max: DebugOnboardingAnimController.maxTime,
                    onChanged: c.seek,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${t.toStringAsFixed(2)} s',
                    style: AppText.caption,
                  ),
                ),
              ],
            ),
          ),
          Obx(
            () => SegmentedButton<double>(
              emptySelectionAllowed: true,
              segments: [
                for (final s in DebugOnboardingAnimController.speeds)
                  ButtonSegment(value: s, label: Text('${s}x')),
              ],
              selected: {
                if (c.speedChoice.value != null) c.speedChoice.value!,
                if (c.speedChoice.value == null &&
                    DebugOnboardingAnimController.speeds
                        .contains(OnboardingArtKind.network.speed))
                  OnboardingArtKind.network.speed,
              },
              onSelectionChanged: (v) {
                if (v.isNotEmpty) c.setSpeed(v.first);
              },
            ),
          ),
          Obx(
            () => Row(
              children: [
                Expanded(
                  child: Text(
                    'effective: network ${c.effectiveSpeed(OnboardingArtKind.network)}x '
                    '· buildings ${c.effectiveSpeed(OnboardingArtKind.buildings)}x '
                    '· shield ${c.effectiveSpeed(OnboardingArtKind.shield)}x '
                    '(1x = the HTML${c.speedChoice.value == null ? ', defaults' : ''})',
                    style: AppText.caption,
                  ),
                ),
                if (c.speedChoice.value != null)
                  AppButton.text(
                    label: 'Default',
                    onPressed: c.useDefaultSpeed,
                  ),
              ],
            ),
          ),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                c.isBlueOnly.value ? 'Blue only' : 'Authored colours',
                style: AppText.body,
              ),
              value: c.isBlueOnly.value,
              onChanged: (v) => c.isBlueOnly.value = v,
            ),
          ),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Tier 2 persons: ${c.isTier2.value ? 'on' : 'off'} (network)',
                style: AppText.body,
              ),
              value: c.isTier2.value,
              onChanged: (v) => c.isTier2.value = v,
            ),
          ),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Symmetric layout: ${c.isSymmetric.value ? 'on' : 'off'} (network)',
                style: AppText.body,
              ),
              value: c.isSymmetric.value,
              onChanged: (v) => c.isSymmetric.value = v,
            ),
          ),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                c.isCropped.value ? 'Full width crop' : 'Original viewBox',
                style: AppText.body,
              ),
              value: c.isCropped.value,
              onChanged: (v) => c.isCropped.value = v,
            ),
          ),
          Obx(
            () => SegmentedButton<LabBackdrop>(
              segments: const [
                ButtonSegment(value: LabBackdrop.white, label: Text('White')),
                ButtonSegment(value: LabBackdrop.light, label: Text('Light')),
                ButtonSegment(value: LabBackdrop.dark, label: Text('Dark')),
              ],
              selected: {c.backdrop.value},
              onSelectionChanged: (v) => c.backdrop.value = v.first,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ListenableBuilder(
            listenable: c.frames,
            builder: (context, _) => Text(
              c.frames.count == 0
                  ? 'frames: waiting'
                  : 'fps ${c.frames.fps.toStringAsFixed(0)} · build avg '
                        '${c.frames.avgBuildMs.toStringAsFixed(1)} / worst '
                        '${c.frames.worstBuildMs.toStringAsFixed(1)} ms · raster avg '
                        '${c.frames.avgRasterMs.toStringAsFixed(1)} / worst '
                        '${c.frames.worstRasterMs.toStringAsFixed(1)} ms '
                        '(last ${c.frames.count})',
              style: AppText.caption,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final kind in OnboardingArtKind.values) ...[
            Text(_titles[kind]!, style: AppText.caption),
            const SizedBox(height: AppSpacing.xxs),
            Obx(
              () => Container(
                decoration: BoxDecoration(
                  color: switch (c.backdrop.value) {
                    LabBackdrop.white => AppColors.white,
                    LabBackdrop.light => OnboardingArtPalette.previewLight,
                    LabBackdrop.dark => AppColors.ink,
                  },
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: AppColors.line),
                ),
                child: OnboardingArt(
                  kind: kind,
                  controller: c.art[kind],
                  blueOnly: c.isBlueOnly.value,
                  networkTier2: c.isTier2.value,
                  networkSymmetric: c.isSymmetric.value,
                  window: c.isCropped.value
                      ? OnboardingArtWindow.crop
                      : OnboardingArtWindow.original,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
