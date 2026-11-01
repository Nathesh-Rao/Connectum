import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_view.dart';
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
          const Expanded(
            child: AppStateView(
              state: AppViewState.comingSoon,
              emptyTitle: 'Profile',
              emptyMessage: 'Coming soon.',
              child: SizedBox.shrink(),
            ),
          ),
          AppButton.secondary(
            label: 'Security',
            onPressed: controller.openSecurity,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Experience the introduction',
            onPressed: controller.replayIntroduction,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
