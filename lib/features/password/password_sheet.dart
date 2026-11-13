import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_bottom_sheet.dart';
import 'password_binding.dart';
import 'password_controller.dart';
import 'password_view.dart';

class PasswordSheet {
  PasswordSheet._();

  static int _opened = 0;

  static Future<void> show(BuildContext context, {required bool hasPassword}) {
    final tag = 'password-${++_opened}';
    PasswordBinding(tag: tag).dependencies();
    return AppBottomSheet.show<void>(
      context,
      title: hasPassword ? 'Change your password' : 'Set a password',
      child: PasswordView(controllerTag: tag),
      onDispose: () => Get.delete<PasswordController>(tag: tag),
    );
  }
}
