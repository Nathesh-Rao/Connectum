import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'debug_smart_table_controller.dart';

class DebugSmartTableView extends GetView<DebugSmartTableController> {
  const DebugSmartTableView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text('Smart table (debug)', style: AppText.title),
          ),
          Expanded(
            child: SmartViewTable(
              source: c.source,
              rows: c.rows,
              versions: const {},
              onRefresh: c.reload,
              cache: c.cache,
              footer: const SizedBox(height: AppSpacing.xl),
            ),
          ),
        ],
      ),
    );
  }
}
