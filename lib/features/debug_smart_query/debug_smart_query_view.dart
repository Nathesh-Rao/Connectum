import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'debug_smart_query_controller.dart';

class DebugSmartQueryView extends GetView<DebugSmartQueryController> {
  const DebugSmartQueryView({super.key});

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
            child: Text('Smart query (debug)', style: AppText.title),
          ),
          Expanded(child: SmartViewContent(controller: controller.view)),
        ],
      ),
    );
  }
}
