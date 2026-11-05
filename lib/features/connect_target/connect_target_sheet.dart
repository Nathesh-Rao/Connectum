import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/utils/connect_code.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import 'connect_target_binding.dart';
import 'connect_target_controller.dart';
import 'connect_target_view.dart';

/// The confirm and result sheet for a scanned or opened Connectum code.
class ConnectTargetSheet {
  ConnectTargetSheet._();

  static Future<void> show(BuildContext context, ConnectCode target) {
    ConnectTargetBinding(target).dependencies();
    return AppBottomSheet.show<void>(
      context,
      title: 'Connect',
      child: const ConnectTargetView(),
    ).whenComplete(Get.delete<ConnectTargetController>);
  }
}
