import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_bottom_sheet.dart';
import 'invite_code_binding.dart';
import 'invite_code_controller.dart';
import 'invite_code_view.dart';

class InviteCodeSheet {
  InviteCodeSheet._();

  static Future<void> show(BuildContext context) {
    InviteCodeBinding().dependencies();
    return AppBottomSheet.show<void>(
      context,
      title: 'Have an invite code or link?',
      child: const InviteCodeView(),
    ).whenComplete(Get.delete<InviteCodeController>);
  }
}
