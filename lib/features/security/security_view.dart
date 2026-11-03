import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../data/repositories/e2e_repository.dart';
import 'security_controller.dart';
import 'widgets/device_row.dart';
import 'widgets/late_notice.dart';
import 'widgets/security_sheets.dart';

class SecurityView extends GetView<SecurityController> {
  const SecurityView({super.key});

  static String modeLabel(String mode) => switch (mode) {
    'required' => 'Required for everyone',
    'optional' => 'On (optional)',
    'off' => 'Off',
    _ => 'Unknown',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                AppButton.icon(
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: Get.back,
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(child: Text('Security', style: AppText.title)),
              ],
            ),
          ),
          const AppOfflineBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.xl,
              ),
              child: Obx(() {
                final phase = c.e2e.phase.value;
                final devices = c.devices.toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (SeedUi.isActive) _SeedChips(controller: c),
                    _Line(caption: 'Organisation', value: c.organisation),
                    _Line(
                      caption: 'Secure messaging',
                      value: modeLabel(c.mode),
                    ),
                    _Line(
                      caption: 'Recovery key',
                      value: c.isRecoveryOn ? 'On' : 'Off',
                    ),
                    if (c.lateTitle != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      LateNotice(title: c.lateTitle!, detail: c.lateDetail),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    const Text('My devices', style: AppText.subtitle),
                    const SizedBox(height: AppSpacing.xs),
                    if (devices.isEmpty)
                      Text(
                        c.mode == 'off'
                            ? 'Secure messaging is off in this organisation.'
                            : 'No devices to show yet.',
                        style: AppText.readable,
                      ),
                    for (var i = 0; i < devices.length; i++)
                      DeviceRow(
                        device: devices[i],
                        isThisPhone: c.isThisPhone(devices[i]),
                        hasDivider: i > 0,
                        isBusy: c.busyId.value == devices[i].id,
                        onRemove: c.isOffline || c.isBusy.value
                            ? null
                            : () => SecuritySheets.confirmRemove(
                                context,
                                c,
                                devices[i],
                              ),
                      ),
                    if (c.isOffline)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'You are offline. This is what was saved last time; removing a device needs a connection.',
                          style: AppText.caption,
                        ),
                      ),
                    if (phase == E2eSetupPhase.optedOut ||
                        phase == E2eSetupPhase.removed ||
                        phase == E2eSetupPhase.refused ||
                        phase == E2eSetupPhase.limit) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppButton.primary(
                        label: phase == E2eSetupPhase.limit
                            ? 'See what to remove'
                            : phase == E2eSetupPhase.refused
                            ? 'Retry'
                            : 'Set up this phone',
                        isCentered: true,
                        isLoading: c.isBusy.value,
                        onPressed: phase == E2eSetupPhase.limit
                            ? () => SecuritySheets.openIssue(context, c)
                            : c.setUp,
                      ),
                    ],
                    if (c.problem.value != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(c.problem.value!, style: AppText.error),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      'Encrypted messages can only be read on the devices listed here. This phone can\'t use a recovery key yet: if all your devices are lost, earlier messages can\'t be read again here. Your keys stay on this phone when you sign out or switch organisation, and are deleted if you remove this phone or uninstall the app.',
                      style: AppText.readable,
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.caption, required this.value});

  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        Expanded(child: Text(caption, style: AppText.readable)),
        Text(value, style: AppText.readableStrong),
      ],
    ),
  );
}

class _SeedChips extends StatelessWidget {
  const _SeedChips({required this.controller});

  final SecurityController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Wrap(
      spacing: AppSpacing.xxs,
      children: [
        for (final s in SeedUi.e2eStates)
          ActionChip(
            label: Text(s, style: AppText.caption),
            onPressed: () => SeedUi.applyE2e(controller.e2e, s),
          ),
      ],
    ),
  );
}
