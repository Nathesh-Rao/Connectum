import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_text_field.dart';
import 'password_controller.dart';

class PasswordView extends GetView<PasswordController> {
  const PasswordView({super.key, this.controllerTag});

  final String? controllerTag;

  @override
  String? get tag => controllerTag;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'A password lets you sign in without waiting for a code. The emailed code keeps working.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(() {
            final info = c.info.value;
            if (info == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(info, style: AppText.caption),
            );
          }),
          Obx(() => c.isCodeSent.value ? _Fields(controller: c) : _Send(c)),
        ],
      ),
    );
  }
}

class _Send extends StatelessWidget {
  const _Send(this.c);

  final PasswordController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final error = c.error.value;
          if (error == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(error, style: AppText.error),
          );
        }),
        Obx(
          () => AppButton.primary(
            label: 'Send me a code',
            isCentered: true,
            isLoading: c.isBusy.value,
            onPressed: c.sendCode,
          ),
        ),
      ],
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.controller});

  final PasswordController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: c.code,
          label: 'Code from your email',
          hint: '6 digits',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          maxLength: 6,
          autocorrect: false,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => c.changed(),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: c.newPassword,
            label: 'New password',
            hint: '${PasswordController.minLength} characters or more',
            helperText:
                '${PasswordController.minLength} to ${PasswordController.maxLength} characters.',
            leading: const Icon(
              Icons.lock_outline,
              size: 18,
              color: AppColors.muted,
            ),
            obscureText: c.isHidden.value,
            autocorrect: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: (_) => c.changed(),
            onSubmitted: (_) => c.save(),
            suffix: IconButton(
              tooltip: c.isHidden.value ? 'Show password' : 'Hide password',
              icon: Icon(
                c.isHidden.value
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppColors.muted,
              ),
              onPressed: c.toggleHidden,
            ),
          ),
        ),
        Obx(() {
          final error = c.error.value;
          if (error == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(error, style: AppText.error),
          );
        }),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppButton.primary(
            label: 'Save password',
            isCentered: true,
            isLoading: c.isBusy.value,
            onPressed: c.canSave ? c.save : null,
          ),
        ),
        if (c.hasPassword)
          Center(
            child: Obx(
              () => AppButton.text(
                label: 'Remove my password',
                tone: AppTextButtonTone.accent,
                onPressed: c.canRemove ? c.remove : null,
              ),
            ),
          ),
      ],
    );
  }
}
