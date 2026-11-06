import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../core/widgets/app_invite_card.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/app_success_animation.dart';
import '../../../data/e2e/e2e_texts.dart';
import '../device_limit_controller.dart';
import 'device_card.dart';

/// The sheet for a full device list: the devices as cards, a confirmation
/// before a removal, and the registration of this phone right after. One
/// sheet, whatever happens behind it.
class DeviceLimitSheet {
  DeviceLimitSheet._();

  static Future<void> show(
    BuildContext context,
    DeviceLimitController controller,
  ) {
    final navigator = Navigator.of(context);
    controller.onFinished = () {
      if (navigator.mounted && navigator.canPop()) navigator.pop();
    };
    controller.loadDevices();
    return AppBottomSheet.show<void>(
      context,
      title: E2eTexts.limitTitle,
      titleWidget: Obx(
        () => Text(_title(controller.step.value), style: AppText.title),
      ),
      child: _Body(controller: controller),
    ).whenComplete(() => controller.onFinished = null);
  }

  static String _title(DeviceLimitStep step) => switch (step) {
    DeviceLimitStep.list => E2eTexts.limitTitle,
    DeviceLimitStep.confirm => E2eTexts.removeTitle,
    DeviceLimitStep.registering => E2eTexts.limitRegistering,
    DeviceLimitStep.done => E2eTexts.limitDone,
    DeviceLimitStep.failed => "Couldn't set up this phone",
  };
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final DeviceLimitController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      return switch (c.step.value) {
        DeviceLimitStep.list => _List(controller: c),
        DeviceLimitStep.confirm => _Confirm(controller: c),
        DeviceLimitStep.registering => const _Registering(),
        DeviceLimitStep.done => const _Done(),
        DeviceLimitStep.failed => _Failed(controller: c),
      };
    });
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final DeviceLimitController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final devices = c.devices.toList();
      final note = c.removedNote.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(E2eTexts.limitBody(c.maxDevices), style: AppText.readable),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppHighlightText(
              E2eTexts.removedTemplate,
              values: {'label': note},
              style: AppText.caption,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (c.isLoading.value && devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: AppSpinner(size: AppSpinnerSize.lg, isStandalone: true),
              ),
            )
          else if (c.isLoadFailed.value && devices.isEmpty)
            AppInviteCard(
              title: E2eTexts.limitLoadFailed,
              icon: Icons.error_outline,
              actionLabel: 'Try again',
              onAction: c.loadDevices,
            )
          else
            DeviceCardList(
              devices: devices,
              isThisPhone: c.isThisPhone,
              busyId: c.busyId.value,
              onRemove: c.isOffline() ? null : (d) => c.ask(d),
            ),
          if (c.isOffline())
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'You are offline. Removing a device needs a connection.',
                style: AppText.caption,
              ),
            ),
        ],
      );
    });
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({required this.controller});

  final DeviceLimitController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final d = c.picked.value;
      final name = d == null || d.label.isEmpty ? 'This device' : d.label;
      final when = d == null
          ? ''
          : E2eTexts.ago(DeviceFacts.lastUsed(d), DateTime.now());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHighlightText(E2eTexts.removeBody(when), values: {'name': name}),
          if (c.problem.value != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(c.problem.value!, style: AppText.error),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.primary(
            label: 'Remove',
            isCentered: true,
            isLoading: c.busyId.value != null,
            onPressed: c.confirmRemove,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Cancel', onPressed: c.cancel),
        ],
      );
    });
  }
}

class _Registering extends StatelessWidget {
  const _Registering();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      children: [
        AppSpinner(size: AppSpinnerSize.sm),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(E2eTexts.limitRegisteringBody, style: AppText.readable),
        ),
      ],
    ),
  );
}

class _Done extends StatelessWidget {
  const _Done();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      AppSuccessAnimation(size: AppSpacing.checkBadge),
      SizedBox(height: AppSpacing.xs),
      Text(E2eTexts.limitDoneBody, style: AppText.readable),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.controller});

  final DeviceLimitController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            E2eTexts.couldNotStart(c.failure.value ?? ''),
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton.primary(
            label: 'Try again',
            isCentered: true,
            onPressed: c.registerAgain,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'See devices', onPressed: c.backToList),
        ],
      ),
    );
  }
}
