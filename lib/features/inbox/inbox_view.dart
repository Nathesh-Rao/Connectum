import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_pill_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import 'inbox_controller.dart';

/// The Inbox tab, as a sample of the design: nothing is read, nothing is sent
/// and nothing moves.
class InboxView extends GetView<InboxController> {
  const InboxView({super.key});

  static const emptyTitle = 'You are all clear.';
  static const emptyMessage = 'Nothing is waiting for you.';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      hasOuterBottomBar: true,
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text('Inbox', style: AppText.heading),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Obx(
              () => AppPillBar(
                pills: [
                  for (var i = 0; i < InboxController.filters.length; i++)
                    AppPill(
                      label: InboxController.filters[i],
                      count: i == InboxController.filters.length - 1
                          ? InboxController.broadcastSample
                          : 0,
                      kind: AppPillKind.violet,
                    ),
                ],
                selected: c.selected.value,
                onSelected: c.select,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: AppTextField(
              hint: 'Search mail',
              minHeight: AppSpacing.searchHeight,
              fillColor: AppColors.searchFill,
              borderColor: Colors.transparent,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.xs),
              ),
              leading: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.muted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                const Expanded(
                  child: Text('0 messages', style: AppText.caption),
                ),
                AppButton.icon(
                  icon: Icons.refresh,
                  semanticLabel: 'Refresh',
                  onPressed: () {},
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppButton.secondary(
                label: 'Visualize tasks & tickets',
                onPressed: null,
              ),
            ),
          ),
          const Expanded(child: _AllClear()),
        ],
      ),
    );
  }
}

/// The calm empty picture, drawn from tokens: a check in a soft violet disc
/// inside a lighter ring.
class _AllClear extends StatelessWidget {
  const _AllClear();

  static const _ring = 96.0;
  static const _disc = 64.0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _ring,
            height: _ring,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.searchFill,
            ),
            child: Container(
              width: _disc,
              height: _disc,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.violetTint,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 32,
                color: AppColors.purple,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(InboxView.emptyTitle, style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xxs),
          const Text(InboxView.emptyMessage, style: AppText.readable),
        ],
      ),
    );
  }
}
