import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'chats_controller.dart';

class ChatsView extends GetView<ChatsController> {
  const ChatsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showOfflineBar: true,
      body: Center(child: Text('Chats', style: AppText.title)),
    );
  }
}
