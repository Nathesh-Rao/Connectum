import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import 'gallery_auth_controller.dart';

class GalleryAuthView extends GetView<GalleryAuthController> {
  const GalleryAuthView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton.icon(
              icon: Icons.arrow_back,
              semanticLabel: 'Back',
              onPressed: Get.back,
            ),
          ),
          const Spacer(),
          const Text('Sign in', style: AppText.heading),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Auth-style screen: open the keyboard and check the fields stay visible.',
            style: AppText.readable,
          ),
          const Spacer(),
          AppTextField(
            controller: controller.email,
            label: 'Email',
            hint: 'you@company.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: controller.code,
            label: 'Code',
            hint: '6-digit code',
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton.primary(
            label: 'Continue',
            icon: Icons.arrow_forward,
            onPressed: () => FocusScope.of(context).unfocus(),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
