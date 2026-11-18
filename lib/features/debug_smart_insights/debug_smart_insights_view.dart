import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_tones.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_speed_dial.dart';
import '../smart_view/smart_view_view.dart';
import '../smart_view/widgets/sv_charts_sheet.dart';
import '../smart_view/widgets/sv_kpi_sheet.dart';
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
