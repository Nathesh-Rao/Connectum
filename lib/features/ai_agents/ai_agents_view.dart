import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_view.dart';
import 'ai_agents_controller.dart';

class AiAgentsView extends GetView<AiAgentsController> {
  const AiAgentsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(
      hasOuterBottomBar: true,
      body: AppStateView(
        state: AppViewState.comingSoon,
        emptyTitle: 'AI Agents',
        emptyMessage: 'Coming soon.',
        child: SizedBox.shrink(),
      ),
    );
  }
}
