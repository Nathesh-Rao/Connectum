import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_ambient_backdrop.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_id_copy_strip.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_success_animation.dart';
import 'enterprise_created_controller.dart';

class EnterpriseCreatedView extends GetView<EnterpriseCreatedController> {
  const EnterpriseCreatedView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      ambient: AppAmbientVariant.access,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Center(child: AppSuccessAnimation()),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Your enterprise is ready',
            style: AppText.heading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(c.name, style: AppText.subtitle, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xl),
          Obx(
            () => AppIdCopyStrip(
              id: c.enterpriseId,
              isCopied: c.isCopied.value,
              onTap: c.copyId,
            ),
          ),
          const Spacer(flex: 2),
          AppButton.primary(
            label: 'Continue',
            icon: Icons.chevron_right,
            onPressed: c.continueToChats,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
