import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/e2e/e2e_models.dart';
import '../../../data/repositories/e2e_repository.dart';
import '../security_controller.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../data/e2e/e2e_texts.dart';
import 'device_card.dart';
import 'device_limit_sheet.dart';

/// The sheets of secure-messaging setup: device limit reached, removed from
/// the list, refused. Plain words; a device is never removed without a
/// confirmation of its own. Only one of them is open at a time.
class SecuritySheets {
  SecuritySheets._();

  static bool _isIssueOpen = false;

  /// The sheet for a full device list, with the devices in it. Does nothing
  /// while a setup sheet is open, or when this organisation's one showing was
  /// already used (unless [isRequested]: the person asked for it).
  static Future<void> openLimit(
    BuildContext context,
    SecurityController c, {
    bool isRequested = false,
  }) async {
    final org = c.orgKey;
    if (org == null || _isIssueOpen) return;
    if (!SecurityController.limitGate.tryOpen(org, isRequested: isRequested)) {
      return;
    }
    final sheet = c.limitController();
    c.activeLimit = sheet;
    try {
      await DeviceLimitSheet.show(context, sheet);
    } finally {
      c.activeLimit = null;
      SecurityController.limitGate.closed();
    }
  }

  /// The sheet for a removed or refused setup.
  static Future<void> openIssue(BuildContext context, SecurityController c) {
    if (_isIssueOpen || SecurityController.limitGate.isOpen) {
      return Future.value();
    }
    _isIssueOpen = true;
    final phase = c.e2e.phase.value;
    final title = switch (phase) {
      E2eSetupPhase.removed =>
        'This phone was removed from your encryption devices',
      _ => "Couldn't set up secure messaging",
    };
    return AppBottomSheet.show<void>(
      context,
      title: title,
      titleWidget: Obx(
        () => Text(
          c.e2e.phase.value == E2eSetupPhase.ready ? E2eTexts.limitDone : title,
          style: AppText.title,
        ),
      ),
      child: _Issue(controller: c, kind: phase),
    ).whenComplete(() => _isIssueOpen = false);
  }

  /// Asks before a removal and runs it. Returns true when it was removed.
  static Future<void> confirmRemove(
    BuildContext context,
    SecurityController c,
    E2eDevicePublic device,
  ) => AppBottomSheet.show<void>(
    context,
    title: E2eTexts.removeTitle,
    child: _ConfirmRemove(controller: c, device: device),
  );
}

class _Issue extends StatelessWidget {
  const _Issue({required this.controller, required this.kind});

  final SecurityController controller;

  /// The phase the sheet was opened for: it fixes the body, so title and body
  /// always belong together. Only "ready" replaces both (set up now).
  final E2eSetupPhase kind;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final phase = c.e2e.phase.value == E2eSetupPhase.ready
          ? E2eSetupPhase.ready
          : kind;
      final children = <Widget>[];
      switch (phase) {
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
                    ? E2eTexts.couldNotStart('the server refused the setup.')
                    : E2eTexts.couldNotStart(c.e2e.issueReason.value),
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
            ..add(const Text(E2eTexts.limitDoneBody, style: AppText.readable))
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
    final name = device.label.isEmpty ? 'This device' : device.label;
    final when = E2eTexts.ago(DeviceFacts.lastUsed(device), DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppHighlightText(
          isThis ? E2eTexts.removeThisBody : E2eTexts.removeBody(when),
          values: {'name': name},
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
