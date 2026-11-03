import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/e2e/e2e_models.dart';
import '../../../data/repositories/e2e_repository.dart';
import '../security_controller.dart';
import 'device_row.dart';

/// The sheets of secure-messaging setup: device limit reached, removed from
/// the list, refused. Plain words; a device is never removed without a
/// confirmation of its own.
class SecuritySheets {
  SecuritySheets._();

  static Future<void> openIssue(BuildContext context, SecurityController c) =>
      AppBottomSheet.show<void>(
        context,
        title: switch (c.e2e.phase.value) {
          E2eSetupPhase.limit => 'Device limit reached',
          E2eSetupPhase.removed =>
            'This phone was removed from your encryption devices',
          _ => "Couldn't set up secure messaging",
        },
        child: _Issue(controller: c),
      );

  /// Asks before a removal and runs it. Returns true when it was removed.
  static Future<void> confirmRemove(
    BuildContext context,
    SecurityController c,
    E2eDevicePublic device,
  ) => AppBottomSheet.show<void>(
    context,
    title: 'Remove this device?',
    child: _ConfirmRemove(controller: c, device: device),
  );
}

class _Issue extends StatelessWidget {
  const _Issue({required this.controller});

  final SecurityController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final phase = c.e2e.phase.value;
      final children = <Widget>[];
      switch (phase) {
        case E2eSetupPhase.limit:
          children
            ..add(
              Text(
                "You've reached the limit of ${c.e2e.maxDevices.value} devices for secure messaging. Remove one you no longer use, and this phone will be set up straight after.",
                style: AppText.readable,
              ),
            )
            ..add(const SizedBox(height: AppSpacing.sm))
            ..addAll([
              for (var i = 0; i < c.devices.length; i++)
                DeviceRow(
                  device: c.devices[i],
                  isThisPhone: c.isThisPhone(c.devices[i]),
                  hasDivider: i > 0,
                  isBusy: c.busyId.value == c.devices[i].id,
                  onRemove: c.isBusy.value
                      ? null
                      : () => SecuritySheets.confirmRemove(
                          context,
                          c,
                          c.devices[i],
                        ),
                ),
            ]);
        case E2eSetupPhase.removed:
          children
            ..add(
              const Text(
                "Set this phone up again to read new encrypted messages here. Messages you couldn't read before stay unreadable.",
                style: AppText.readable,
              ),
            )
            ..add(const SizedBox(height: AppSpacing.lg))
            ..add(
              AppButton.primary(
                label: 'Set up again',
                isCentered: true,
                isLoading: c.isBusy.value,
                onPressed: c.setUp,
              ),
            );
        case E2eSetupPhase.refused:
          children
            ..add(
              Text(
                c.e2e.issueReason.value.isEmpty
                    ? 'The server refused the setup.'
                    : 'The server said: ${c.e2e.issueReason.value}',
                style: AppText.readable,
              ),
            )
            ..add(const SizedBox(height: AppSpacing.lg))
            ..add(
              AppButton.primary(
                label: 'Retry',
                isCentered: true,
                isLoading: c.isBusy.value,
                onPressed: c.setUp,
              ),
            );
        default:
          children
            ..add(
              const Text(
                'Secure messaging is set up on this phone.',
                style: AppText.readable,
              ),
            )
            ..add(const SizedBox(height: AppSpacing.lg))
            ..add(
              AppButton.secondary(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            );
      }
      final problem = c.problem.value;
      if (problem != null) {
        children
          ..add(const SizedBox(height: AppSpacing.sm))
          ..add(Text(problem, style: AppText.error));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    });
  }
}

class _ConfirmRemove extends StatelessWidget {
  const _ConfirmRemove({required this.controller, required this.device});

  final SecurityController controller;
  final E2eDevicePublic device;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isThis = c.isThisPhone(device);
    final name = device.label.isEmpty ? 'this device' : device.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isThis
              ? "You won't be able to read new encrypted messages on this phone until you set it up again. The keys on this phone are deleted."
              : "$name won't be able to read new encrypted messages until it is set up again. Messages it already received stay readable there only if its keys are still on it.",
          style: AppText.readable,
        ),
        Obx(
          () => c.problem.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(c.problem.value!, style: AppText.error),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: 'Remove',
            isCentered: true,
            isLoading: c.isBusy.value,
            onPressed: () async {
              final isOk = await c.remove(device);
              if (isOk && context.mounted) Navigator.of(context).pop();
            },
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
