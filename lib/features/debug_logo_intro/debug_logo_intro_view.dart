import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/logo_intro/logo_intro.dart';
import '../../core/widgets/logo_loader/logo_loader.dart';
import 'debug_logo_intro_controller.dart';

/// Debug only: replay, scrub and tune the LogoIntro next to the old LogoLoader.
class DebugLogoIntroView extends GetView<DebugLogoIntroController> {
  const DebugLogoIntroView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      isScrollable: true,
      padding: const EdgeInsets.all(AppSpacing.page),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(
            () => ColoredBox(
              color: controller.isNavy.value ? AppColors.ink : AppColors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    LogoIntro(
                      size: 220,
                      controller: controller.intro,
                      speed: controller.speed.value,
                      timeOverride: controller.isScrubbing.value
                          ? controller.time
                          : null,
                      blurLetters: controller.hasBlur.value,
                      glowFinal: controller.glowFinal.value,
                      ink: controller.isNavy.value
                          ? AppColors.white
                          : AppColors.ink,
                    ),
                    GestureDetector(
                      onTap: controller.toggleLoader,
                      child: LogoLoader(
                        controller: controller.loader,
                        size: 80,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            'Left: LogoIntro. Right: old LogoLoader (tap to start / stop).',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.page),
          Obx(
            () => Slider(
              value: controller.isScrubbing.value
                  ? controller.time.value.clamp(0, LogoIntro.duration)
                  : 0,
              max: LogoIntro.duration,
              onChanged: controller.scrub,
            ),
          ),
          Obx(
            () => Text(
              controller.isScrubbing.value
                  ? 't = ${controller.time.value.toStringAsFixed(2)} s of '
                        '${LogoIntro.duration.toStringAsFixed(2)} s (scrubbing)'
                  : 'Playing. Drag to scrub.',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.page),
          Obx(
            () => Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in DebugLogoIntroController.speeds)
                  ChoiceChip(
                    label: Text('${s}x'),
                    selected: controller.speed.value == s,
                    onSelected: (_) => controller.speed.value = s,
                  ),
                FilterChip(
                  label: const Text('navy + white ink'),
                  selected: controller.isNavy.value,
                  onSelected: (v) => controller.isNavy.value = v,
                ),
              ],
            ),
          ),
          Obx(
            () => SwitchListTile(
              title: const Text('Blur letters'),
              value: controller.hasBlur.value,
              onChanged: (v) => controller.hasBlur.value = v,
            ),
          ),
          Obx(
            () => Row(
              children: [
                Text('Glow final', style: AppText.body),
                Expanded(
                  child: Slider(
                    value: controller.glowFinal.value,
                    onChanged: (v) => controller.glowFinal.value = v,
                  ),
                ),
                Text(
                  controller.glowFinal.value.toStringAsFixed(2),
                  style: AppText.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.page),
          AppButton.primary(
            label: 'Replay',
            onPressed: controller.replay,
            isCentered: true,
          ),
        ],
      ),
    );
  }
}
