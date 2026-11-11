import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'ai_agents_controller.dart';

class AiAgentsView extends GetView<AiAgentsController> {
  const AiAgentsView({super.key});

  static const robotAsset = 'assets/lottie/robot.json';
  static const title = 'Launching soon';
  static const subtitle =
      "We're currently mastering the agents. We'll launch as soon as possible.";

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      body: _ComingSoon(),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  static const _stillFrame = AlwaysStoppedAnimation<double>(0);

  @override
  Widget build(BuildContext context) {
    final isStill = MediaQuery.disableAnimationsOf(context);
    final isNarrow =
        MediaQuery.sizeOf(context).width < 340 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final isCompact = height < AppSpacing.agentsCompactHeight;
        final side = [
          height * (isCompact ? 0.4 : 0.5),
          constraints.maxWidth,
          AppSpacing.agentsLottieMax,
        ].reduce((a, b) => a < b ? a : b);
        final gap = isCompact ? AppSpacing.md : AppSpacing.xl;
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Robot animation',
                    excludeSemantics: true,
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: Lottie.asset(
                        AiAgentsView.robotAsset,
                        controller: isStill ? _stillFrame : null,
                        animate: !isStill,
                        repeat: true,
                        frameRate: FrameRate.composition,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  SizedBox(height: gap),
                  Text(
                    AiAgentsView.title,
                    style: isNarrow
                        ? AppText.displayBrand.copyWith(fontSize: 28)
                        : AppText.displayBrand,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.agentsCopyMaxWidth,
                    ),
                    child: const Text(
                      AiAgentsView.subtitle,
                      style: AppText.supporting,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
