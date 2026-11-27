import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'debug_smart_insights_controller.dart';

class DebugSmartInsightsView extends GetView<DebugSmartInsightsController> {
  const DebugSmartInsightsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller.view;
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('Smart insights (debug)', style: AppText.title),
              ),
              Expanded(child: SmartViewContent(controller: c)),
            ],
          ),
          Positioned.fill(
            child: AppSpeedDial(
              options: [
                AppSpeedDialOption(
                  label: 'Add record',
                  icon: Icons.add,
                  onSelected: () => AppNotices.success('Add record tapped'),
                ),
                AppSpeedDialOption(
                  label: 'KPI',
                  icon: Icons.insights_outlined,
                  tone: AppTones.green,
                  onSelected: () => SvKpiSheet.show(context, c),
                ),
                AppSpeedDialOption(
                  label: 'Charts',
                  icon: Icons.bar_chart_rounded,
                  tone: AppTones.violet,
                  onSelected: () => SvChartsSheet.show(context, c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
