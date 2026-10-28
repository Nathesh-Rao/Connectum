import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_animation_placeholder.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_flex_gap.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/onboarding_stage.dart';
import 'onboarding_controller.dart';

class OnboardingView extends GetView<OnboardingController> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final slides = OnboardingController.slides;
    return AppScaffold(
      isScrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const AppLogo(width: AppSpacing.headerLogoWidth),
              const SizedBox(width: AppSpacing.xs),
              const Text('Connectum', style: AppText.wordmark),
              const Spacer(),
              AppButton.text(label: 'Skip', onPressed: c.finish),
            ],
          ),
          const AppFlexGap(flex: 32, min: 4, max: 40),
          Flexible(
            flex: 270,
            child: Obx(
              () => OnboardingStage(
                slide: c.page.value,
                controller: c.pageController,
                itemCount: slides.length,
                onPageChanged: c.onPageChanged,
                itemBuilder: (context, i) => ClipRRect(
                  borderRadius: AppRadius.mdAll,
                  child: AppAnimationPlaceholder(
                    name: slides[i].animation,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ),
          ),
          const AppFlexGap(flex: 82, min: 8, max: 96),
          _Dots(controller: c),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: AppSpacing.slideCopyHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) c.next();
                if (v > 200) c.back();
              },
              child: PageView.builder(
                controller: c.copyController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: slides.length,
                itemBuilder: (context, i) => _Copy(slide: slides[i]),
              ),
            ),
          ),
          const AppFlexGap(flex: 30, min: 8, max: 40),
          Obx(
            () => AppButton.primary(
              label: c.isLast ? 'Get Started' : 'Continue',
              icon: Icons.chevron_right,
              onPressed: c.next,
            ),
          ),
          Obx(
            () => Row(
              children: [
                if (c.page.value > 0)
                  AppButton.text(label: 'Back', onPressed: c.back)
                else
                  const SizedBox(height: AppSpacing.minTapTarget),
                const Spacer(),
                Text(
                  '${(c.page.value + 1).toString().padLeft(2, '0')} / 0${slides.length}',
                  style: AppText.eyebrow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.controller});

  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    // Each dot sits in a 28px cell and the row starts 9px left of the page
    // margin, like the prototype.
    return Transform.translate(
      offset: const Offset(-9, 0),
      child: Obx(
        () => Row(
          children: [
            for (var i = 0; i < OnboardingController.slides.length; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.goTo(i),
                child: SizedBox(
                  width: AppSpacing.dotCell,
                  height: AppSpacing.minTapTarget,
                  child: Center(
                    child: AnimatedContainer(
                      duration: AppDurations.fast,
                      curve: AppCurves.out,
                      width: i == controller.page.value
                          ? AppSpacing.dotActiveWidth
                          : AppSpacing.dotWidth,
                      height: AppSpacing.dotWidth,
                      decoration: BoxDecoration(
                        color: i == controller.page.value
                            ? AppColors.accent
                            : AppColors.inputBorder,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Copy extends StatelessWidget {
  const _Copy({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.slideTitleMaxWidth,
          ),
          child: Text(slide.title, style: AppText.heroSlide),
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.slideCopyMaxWidth,
          ),
          child: Text(slide.copy, style: AppText.slideCopy),
        ),
      ],
    );
  }
}
