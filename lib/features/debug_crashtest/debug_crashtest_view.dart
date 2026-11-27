import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'debug_crashtest_controller.dart';

/// Debug only (see "Before release" in CLAUDE.md): triggers every kind of
/// report so they can be checked in the Crashlytics console.
class DebugCrashTestView extends GetView<DebugCrashTestController> {
  const DebugCrashTestView({super.key});

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text('$label: $value', style: AppText.readable),
  );

  Future<void> _confirmCrash(BuildContext context) async {
    final isSure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crash the app?'),
        content: const Text('This closes the app with a native crash.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Crash'),
          ),
        ],
      ),
    );
    if (isSure ?? false) controller.crashNative();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          const Text('Crash test', style: AppText.display),
          const SizedBox(height: AppSpacing.md),
          Obx(() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(
                  'Firebase initialised',
                  controller.isFirebaseReady ? 'yes' : 'no',
                ),
                _row('Collection enabled', controller.isEnabled ? 'yes' : 'no'),
                _row('Build mode', controller.buildMode),
                _row('Identity set', controller.identityText),
                const Text('Last breadcrumbs sent:', style: AppText.readable),
                for (final c in controller.crumbs)
                  Text(
                    c,
                    style: AppText.readable.copyWith(color: AppColors.muted),
                  ),
              ],
            );
          }),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Fatal crashes upload on the NEXT app launch; relaunch from the '
            'phone launcher, not from flutter run.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: 'Send breadcrumb',
            onPressed: controller.sendBreadcrumb,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Record non-fatal error',
            onPressed: controller.recordNonFatal,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Throw async error (unhandled)',
            onPressed: controller.throwAsync,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Throw error in a Flutter callback',
            onPressed: controller.throwInCallback,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.primary(
            label: 'Fatal native crash',
            onPressed: () => _confirmCrash(context),
          ),
        ],
      ),
    );
  }
}
