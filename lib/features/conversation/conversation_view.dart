import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'conversation_controller.dart';

class ConversationView extends GetView<ConversationController> {
  const ConversationView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showOfflineBar: true,
      body: Center(
        child: Text(
          'Conversation ${controller.conversationId}',
          style: AppText.title,
        ),
      ),
    );
  }
}
