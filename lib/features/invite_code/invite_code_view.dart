import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import 'invite_code_controller.dart';

class InviteCodeView extends GetView<InviteCodeController> {
  const InviteCodeView({super.key, this.controllerTag});

  final String? controllerTag;

  @override
  String? get tag => controllerTag;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Type or paste the code or link you were given.',
          style: AppText.readable,
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: c.input,
            label: 'Invite code or link',
            hint: 'XXXX-XXXX or https://connectum.app/connect/…',
            errorText: c.error.value,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onChanged: (_) => c.error.value = null,
            onSubmitted: (_) => c.submit(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.primary(
          label: 'Use this invite',
          isCentered: true,
          onPressed: c.submit,
        ),
      ],
    );
  }
}
