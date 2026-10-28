import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Equal-width tabs in a bordered container with a pill that slides between
/// them. The pill, the label colour and the label weight all follow the
/// controller's animation. Dragging along the bar changes tabs too.
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.controller, required this.labels});

  static const _tabHeight = 40.0;

  final TabController controller;
  final List<String> labels;

  Duration _duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : AppDurations.base;

  void _goTo(BuildContext context, int index) {
    if (index == controller.index) return;
    controller.animateTo(
      index,
      duration: _duration(context),
      curve: AppCurves.out,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.line),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          // LayoutBuilder can't be measured by an IntrinsicHeight parent, so the
          // bar's own width is read here (minus its padding and border).
          final width = context.size?.width ?? 0;
          final slot = (width - 2 * (AppSpacing.xxs + 1)) / labels.length;
          if (slot <= 0) return;
          _goTo(
            context,
            (d.localPosition.dx / slot).floor().clamp(0, labels.length - 1),
          );
        },
        child: TabBar(
          controller: controller,
          onTap: (i) => _goTo(context, i),
          padding: EdgeInsets.zero,
          labelPadding: EdgeInsets.zero,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: const BoxDecoration(
            color: AppColors.accentTint,
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.segment)),
          ),
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.muted,
          labelStyle: AppText.segmentSelected,
          unselectedLabelStyle: AppText.segment,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          tabs: [
            for (final label in labels) Tab(height: _tabHeight, text: label),
          ],
        ),
      ),
    );
  }
}
