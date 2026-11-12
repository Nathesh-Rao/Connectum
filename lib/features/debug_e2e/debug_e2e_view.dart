import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import '../security/widgets/device_limit_sheet.dart';
import 'debug_e2e_controller.dart';

class DebugE2eView extends GetView<DebugE2eController> {
  const DebugE2eView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Debug: E2E vectors', style: AppText.heading),
          const SizedBox(height: AppSpacing.sm),
          Obx(() {
            final isRunning = c.isRunning.value;
            final isPassed = c.isAllPassed;
            final label = isRunning
                ? 'Running...'
                : c.results.isEmpty
                ? 'No result'
                : isPassed
                ? 'ALL ${c.results.length} PASSED'
                : '${c.failedCount} FAILED of ${c.results.length}';
            return Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isRunning || c.results.isEmpty
                    ? AppColors.noFill
                    : isPassed
                    ? AppColors.yesFill
                    : AppColors.primaryTint,
                borderRadius: AppRadius.mdAll,
              ),
              child: Text(
                label,
                style: AppText.subtitle.copyWith(
                  color: isPassed ? AppColors.yesText : AppColors.error,
                ),
              ),
            );
          }),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in c.results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                    child: Text(
                      '${r.isPassed ? 'PASS' : 'FAIL'}  ${r.name}'
                      '${r.detail.isEmpty ? '' : ' (${r.detail})'}',
                      style: AppText.readable.copyWith(
                        color: r.isPassed ? AppColors.yesText : AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => AppButton.secondary(
              label: 'Run again',
              onPressed: c.isRunning.value ? null : c.run,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Show device limit sheet (sample devices)',
            onPressed: () => DeviceLimitSheet.show(context, c.sampleLimit()),
          ),
          const SizedBox(height: AppSpacing.xs),
          Obx(
            () => AppButton.secondary(
              label: 'Measure hand-on crypto (400 messages)',
              onPressed: c.isBusy.value ? null : c.benchmarkHandOn,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Device(controller: c),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Device extends StatelessWidget {
  const _Device({required this.controller});

  final DebugE2eController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final e2e = c.e2e;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('This phone and the server', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xs),
        Obx(() {
          final reason = c.blockedReason;
          final id = e2e.deviceId.value;
          final isKnown = e2e.isStatusKnown.value;
          final lines = [
            'Organisation: ${c.session.orgId ?? '-'}',
            'User: ${c.session.userId ?? '-'}',
            if (reason != null) 'Cannot read the server: $reason',
            'Mode: ${isKnown ? e2e.mode.value : 'unknown (not read yet)'}',
            'Max devices: ${isKnown ? e2e.maxDevices.value : '-'}',
            'Keys on this phone: ${e2e.hasKeys.value ? 'YES (${_short(id)})' : 'NO'}',
            'This phone registered: ${isKnown ? (e2e.isRegistered ? 'YES' : 'NO') : 'unknown'}',
            'Recovery key: ${isKnown ? (e2e.isRecoveryOn.value ? 'on' : 'off') : 'unknown'}',
            'My registered devices (${e2e.myDevices.length}, recovery key not counted):',
            for (final d in e2e.myDevices)
              '  ${_short(d.id)}  ${d.label.isEmpty ? '(no label)' : d.label}'
                  '  added ${_date(d.ts)}${d.id == id ? '  <- this phone' : ''}',
            if (e2e.lastError.value.isNotEmpty)
              'Last error: ${e2e.lastError.value}',
          ];
          return Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.noFill,
              borderRadius: AppRadius.mdAll,
            ),
            child: Text(lines.join('\n'), style: AppText.readable),
          );
        }),
        const SizedBox(height: AppSpacing.xs),
        AppTextField(controller: c.label, label: 'Device label'),
        const SizedBox(height: AppSpacing.xs),
        Obx(() {
          final text = c.message.value;
          return text.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(text, style: AppText.readable),
                );
        }),
        Obx(() {
          final reason = c.blockedReason;
          final registerReason = c.registerBlockedReason;
          final isOff = reason != null || c.isBusy.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton.secondary(
                label: 'Refresh status (read only)',
                onPressed: isOff ? null : c.refreshDevices,
              ),
              if (reason != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(
                    'Disabled: $reason',
                    style: AppText.caption.copyWith(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              if (!e2e.isRegistered) ...[
                AppButton.primary(
                  label: c.armed.value == 'register'
                      ? 'Tap again to confirm: register this phone'
                      : 'Register this phone',
                  onPressed: c.isBusy.value || registerReason != null
                      ? null
                      : c.register,
                ),
                if (registerReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      'Disabled: $registerReason',
                      style: AppText.caption.copyWith(color: AppColors.error),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.xs),
              if (e2e.hasKeys.value)
                AppButton.text(
                  label: c.armed.value == 'remove'
                      ? 'Tap again: delete keys and remove this device'
                      : 'Remove this device',
                  tone: AppTextButtonTone.accent,
                  onPressed: isOff ? null : c.removeThisDevice,
                ),
            ],
          );
        }),
      ],
    );
  }

  static String _short(String id) =>
      id.length > 8 ? '${id.substring(0, 8)}...' : id;

  static String _date(int ts) {
    if (ts <= 0) return '-';
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
