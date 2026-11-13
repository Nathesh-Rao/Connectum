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

/// Debug only: replay, scrub and tune the logo intro next to the old LogoLoader.
class DebugLogoIntroView extends GetView<DebugLogoIntroController> {
  const DebugLogoIntroView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      padding: const EdgeInsets.all(AppSpacing.page),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(
            () => ColoredBox(
              color: controller.isNavy.value ? AppColors.ink : AppColors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: LogoIntroFrame(
                    time: controller.time,
                    textColor: controller.isNavy.value
                        ? AppColors.white
                        : AppColors.ink,
                    isLabelled: controller.isLabelled.value,
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: controller.time,
            builder: (_, t, _) => Slider(
              value: t.clamp(0, kLogoIntroTotalMs),
              max: kLogoIntroTotalMs,
              onChanged: controller.scrub,
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: controller.time,
            builder: (_, t, _) => Text(
              't = ${t.round()} ms / ${kLogoIntroTotalMs.round()}',
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
                    onSelected: (_) => controller.setSpeed(s),
                  ),
                FilterChip(
                  label: const Text('navy'),
                  selected: controller.isNavy.value,
                  onSelected: (v) => controller.isNavy.value = v,
                ),
                FilterChip(
                  label: const Text('s values'),
                  selected: controller.isLabelled.value,
                  onSelected: (v) => controller.isLabelled.value = v,
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
          const SizedBox(height: AppSpacing.page),
          Text(
            'Old LogoLoader (tap to start / stop)',
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: controller.toggleLoader,
            child: Center(
              child: LogoLoader(controller: controller.loader, size: 120),
            ),
          ),
        ],
      ),
    );
  }
}
