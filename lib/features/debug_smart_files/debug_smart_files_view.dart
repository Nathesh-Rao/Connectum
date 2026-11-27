import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import '../../data/smart_view/sv_columns.dart';
import 'debug_smart_files_controller.dart';

class DebugSmartFilesView extends GetView<DebugSmartFilesController> {
  const DebugSmartFilesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final columns = SmartViewColumns.of(c.source);
    void open(files, index) =>
        SvFilePreviewDialog.show(context, c.newPreview(files, index));
    return AppScaffold(
      isScrollable: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Smart View files', style: AppText.title),
          const SizedBox(height: AppSpacing.md),
          for (final row in c.rows.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSv.cardGap),
              child: SmartViewCard(
                data: columns.cardOf(row),
                isExpanded: true,
                onToggle: () {},
                onOpenFiles: open,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 420,
            child: SmartViewTable(
              source: c.source,
              rows: c.rows,
              versions: const {},
              onRefresh: () async {},
              footer: const SizedBox.shrink(),
              onOpenFiles: open,
            ),
          ),
        ],
      ),
    );
  }
}
