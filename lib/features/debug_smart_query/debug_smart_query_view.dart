import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import '../smart_view/smart_view_view.dart';
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
