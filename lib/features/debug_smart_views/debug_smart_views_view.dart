import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'debug_smart_views_controller.dart';

class DebugSmartViewsView extends GetView<DebugSmartViewsController> {
  const DebugSmartViewsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text('Saved views', style: AppText.title),
          ),
          Expanded(child: SmartViewContent(controller: controller.view)),
        ],
      ),
    );
  }
}
