import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_qr.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import 'debug_qr_controller.dart';

/// Debug only: opens the QR sheet on sample data or on the real `connect.my`.
class DebugQrView extends GetView<DebugQrController> {
  const DebugQrView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Debug: QR sheet', style: AppText.heading),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Samples need no server. Share works for real.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: 'Real data (connect.my)',
            onPressed: () => controller.openReal(context),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Samples', style: AppText.readableStrong),
          const SizedBox(height: AppSpacing.xs),
          for (final scenario in SeedQr.scenarios) ...[
            AppButton.secondary(
              label: scenario.label,
              onPressed: () => controller.open(scenario, context),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}
