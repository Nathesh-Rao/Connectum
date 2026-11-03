import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class AppFilterTab {
  const AppFilterTab({required this.label, this.count = 0});

  final String label;
  final int count;
}

/// Text filters with a count badge and an accent underline that slides
/// between them (the TabBar moves it with the controller).
class AppFilterTabs extends StatelessWidget {
  const AppFilterTabs({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<AppFilterTab> tabs;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.only(right: AppSpacing.xl),
          indicatorSize: TabBarIndicatorSize.label,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppColors.accent, width: 2),
          ),
          dividerColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          labelColor: AppColors.accentInk,
          unselectedLabelColor: AppColors.muted,
          labelStyle: AppText.segmentSelected,
          unselectedLabelStyle: AppText.segment,
          tabs: [
            for (final tab in tabs)
              Tab(
                height: AppSpacing.filterTabHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tab.label),
                    if (tab.count > 0) ...[
                      const SizedBox(width: AppSpacing.xs - 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.accentTint,
                          borderRadius: BorderRadius.all(
                            Radius.circular(AppRadius.badge),
                          ),
                        ),
                        child: Text(
                          tab.count > 99 ? '99+' : '${tab.count}',
                          style: AppText.caption.copyWith(
                            color: AppColors.accentInk,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
