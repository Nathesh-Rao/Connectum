import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'ai_agents_controller.dart';

class AiAgentsView extends GetView<AiAgentsController> {
  const AiAgentsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(child: Text('Ai Agents', style: AppText.title)),
    );
  }
}
