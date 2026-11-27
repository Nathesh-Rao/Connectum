import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'debug_smart_drawer_controller.dart';

class DebugSmartDrawerView extends GetView<DebugSmartDrawerController> {
  const DebugSmartDrawerView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => PopScope(
        canPop: !c.isOpen.value,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) c.close();
        },
        child: AppScaffold(
          isScrollable: false,
          padding: EdgeInsets.zero,
          body: AppDrawerShell(
            isOpen: c.isOpen.value,
            onChanged: c.setOpen,
            drawer: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Text('Smart view', style: AppText.title),
                const SizedBox(height: AppSpacing.sm),
                for (
                  var i = 0;
                  i < DebugSmartDrawerController.views.length;
                  i++
                )
                  GestureDetector(
                    onTap: () => c.pick(i),
                    child: Container(
                      height: AppSpacing.drawerRowHeight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: i == c.selected.value
                            ? AppColors.violetTint
                            : Colors.transparent,
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Text(
                        DebugSmartDrawerController.views[i],
                        style: AppText.rowTitle,
                      ),
                    ),
                  ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppButton.icon(
                      icon: Icons.menu,
                      semanticLabel: 'Smart views',
                      onPressed: c.open,
                    ),
                    Text(
                      DebugSmartDrawerController.views[c.selected.value],
                      style: AppText.title,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      AppButton.secondary(label: 'Open', onPressed: c.open),
                      const SizedBox(width: AppSpacing.xs),
                      AppButton.secondary(label: 'Close', onPressed: c.close),
                    ],
                  ),
                ),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    children: [
                      for (var i = 0; i < 12; i++)
                        Container(
                          width: 120,
                          margin: const EdgeInsets.only(right: AppSpacing.xs),
                          decoration: const BoxDecoration(
                            color: AppColors.searchFill,
                            borderRadius: AppRadius.cardAll,
                          ),
                          alignment: Alignment.center,
                          child: Text('Card $i', style: AppText.readable),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
