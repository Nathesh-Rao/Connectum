import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_animation_placeholder.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import 'onboarding_controller.dart';

class OnboardingView extends GetView<OnboardingController> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final slides = OnboardingController.slides;
    return AppScaffold(
      isScrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset('assets/images/connectum_logo.png', width: 26),
              const SizedBox(width: AppSpacing.xs),
              const Text('Connectum', style: AppText.subtitle),
              const Spacer(),
              AppButton.text(label: 'Skip', onPressed: controller.finish),
            ],
          ),
          Expanded(
            child: PageView.builder(
              controller: controller.pageController,
              onPageChanged: controller.onPageChanged,
              itemCount: slides.length,
              itemBuilder: (context, i) => _Slide(slide: slides[i]),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => Row(
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: AppDurations.fast,
                    curve: AppCurves.out,
                    width: i == controller.page.value ? 20 : 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: i == controller.page.value
                          ? AppColors.accent
                          : AppColors.inputBorder,
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => AppButton.primary(
              label: controller.isLast ? 'Get Started' : 'Continue',
              icon: Icons.arrow_forward,
              onPressed: controller.next,
            ),
          ),
          Obx(
            () => Row(
              children: [
                if (controller.page.value > 0)
                  AppButton.text(label: 'Back', onPressed: controller.back)
                else
                  const SizedBox(height: AppSpacing.minTapTarget),
                const Spacer(),
                Text(
                  '${(controller.page.value + 1).toString().padLeft(2, '0')} / 0${slides.length}',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Center(
            child: ClipRRect(
              borderRadius: AppRadius.mdAll,
              child: AppAnimationPlaceholder(
                name: slide.animation,
                width: double.infinity,
                height: 260,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(slide.title, style: AppText.heading),
        const SizedBox(height: AppSpacing.sm),
        Text(slide.copy, style: AppText.readable),
      ],
    );
  }
}
