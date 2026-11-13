import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../authentication/authentication_view.dart';
import 'debug_auth_controller.dart';
import 'scripted_auth_repository.dart';

/// Debug only: the real sign-in screen on a scripted repository. Switch to
/// Password, type anything and press Sign in to see each refusal. The
/// Password sheet of Profile is checked with `--dart-define=DEMO_MODE=true`.
class DebugAuthView extends GetView<DebugAuthController> {
  const DebugAuthView({super.key});

  static const _labels = {
    PasswordOutcome.wrong: 'Wrong password',
    PasswordOutcome.locked: 'Locked',
    PasswordOutcome.lockedWithTime: 'Locked, 20 s',
    PasswordOutcome.network: 'Network error',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Obx(
                () => Row(
                  children: [
                    for (final o in PasswordOutcome.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ChoiceChip(
                          label: Text(_labels[o]!),
                          selected: controller.outcome.value == o,
                          onSelected: (_) => controller.pick(o),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Expanded(
            child: AuthenticationView(controllerTag: DebugAuthController.tag),
          ),
        ],
      ),
    );
  }
}
