import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import 'profile_controller.dart';

class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      hasOuterBottomBar: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Center(child: Text('Profile', style: AppText.title)),
          const SizedBox(height: AppSpacing.xl),
          AppButton.secondary(
            label: 'Experience the introduction',
            onPressed: controller.replayIntroduction,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
