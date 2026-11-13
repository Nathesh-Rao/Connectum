import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_flex_gap.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/onboarding_art_stage.dart';
import 'debug_onboarding_controller.dart';

/// Debug copy of the onboarding screen: same animation slot
/// ([OnboardingArtStage]) as the real one, but finishing only goes back.
class DebugOnboardingView extends GetView<DebugOnboardingController> {
  const DebugOnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final slides = DebugOnboardingController.slides;
    return AppScaffold(
      isScrollable: false,
      // the artwork is full-bleed; everything else keeps the page padding
      padding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.sm),
          _pad(
            Row(
              children: [
                const AppLogo(width: AppSpacing.headerLogoWidth),
                const SizedBox(width: AppSpacing.xs),
                const Text('Connectum', style: AppText.wordmark),
                const Spacer(),
                AppButton.text(label: 'Skip', onPressed: c.finish),
              ],
            ),
          ),
          const AppFlexGap(flex: 32, min: 4, max: 40),
          Flexible(
            flex: 270,
            child: Obx(
              () => OnboardingArtStage(
                slide: c.page.value,
                controller: c.pageController,
                onPageChanged: c.onPageChanged,
              ),
            ),
          ),
          const AppFlexGap(flex: 82, min: 8, max: 96),
          _pad(_Dots(controller: c)),
          const SizedBox(height: AppSpacing.sm),
          _pad(
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
          ),
          const AppFlexGap(flex: 30, min: 8, max: 40),
          _pad(
            Obx(
              () => AppButton.primary(
                label: c.isLast ? 'Get Started' : 'Continue',
                icon: Icons.chevron_right,
                onPressed: c.next,
              ),
            ),
          ),
          _pad(
            Obx(
              () => Row(
                children: [
                  if (c.page.value > 0)
                    AppButton.text(label: 'Back', onPressed: c.back)
                  else
                    const SizedBox(height: AppSpacing.minTapTarget),
                  Expanded(
                    child: Center(
                      child: AppButton.text(
                        label: 'Have an invite code or link?',
                        onPressed: () {},
                      ),
                    ),
                  ),
                  Text(
                    '${(c.page.value + 1).toString().padLeft(2, '0')} / 0${slides.length}',
                    style: AppText.eyebrow,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _pad(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
    child: child,
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.controller});

  final DebugOnboardingController controller;

  @override
  Widget build(BuildContext context) {
    // Each dot sits in a 28px cell and the row starts 9px left of the page
    // margin, like the prototype.
    return Transform.translate(
      offset: const Offset(-9, 0),
      child: Obx(
        () => Row(
          children: [
            for (var i = 0; i < DebugOnboardingController.slides.length; i++)
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
                            ? AppColors.primaryBright
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

  final DebugOnboardingSlide slide;

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
