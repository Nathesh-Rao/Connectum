import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_scaffold.dart';
import '../smart_view/widgets/sv_overview_body.dart';
import 'debug_smart_overview_controller.dart';

class DebugSmartOverviewView extends GetView<DebugSmartOverviewController> {
  const DebugSmartOverviewView({super.key});

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
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xxs,
            ),
            child: Text('Overview', style: AppText.title),
          ),
          Expanded(
            child: SvOverviewBody(
              model: c.model,
              isEmpty: false,
              onOpen: (s) => AppNotices.success('Opens ${s.caption}'),
              onRefresh: c.reload,
            ),
          ),
        ],
      ),
    );
  }
}
