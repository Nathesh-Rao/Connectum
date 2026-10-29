import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_view.dart';
import 'submissions_controller.dart';

class SubmissionsView extends GetView<SubmissionsController> {
  const SubmissionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      hasOuterBottomBar: true,
      body: AppStateView(
        state: AppViewState.comingSoon,
        emptyTitle: 'Submissions',
        emptyMessage: 'Coming soon.',
        child: SizedBox.shrink(),
      ),
    );
  }
}
