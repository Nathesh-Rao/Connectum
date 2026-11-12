import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_bottom_sheet.dart';
import 'invite_code_binding.dart';
import 'invite_code_controller.dart';
import 'invite_code_view.dart';

class InviteCodeSheet {
  InviteCodeSheet._();

  static int _opened = 0;

  static Future<void> show(BuildContext context) {
    final tag = 'invite-code-${++_opened}';
    InviteCodeBinding(tag: tag).dependencies();
    return AppBottomSheet.show<void>(
      context,
      title: 'Have an invite code or link?',
      child: InviteCodeView(controllerTag: tag),
      onDispose: () => Get.delete<InviteCodeController>(tag: tag),
    );
  }
}
