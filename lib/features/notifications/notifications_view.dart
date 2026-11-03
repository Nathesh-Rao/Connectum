import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'notifications_controller.dart';

class NotificationsView extends GetView<NotificationsController> {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(child: Text('Notifications', style: AppText.title)),
    );
  }
}
