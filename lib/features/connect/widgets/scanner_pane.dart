import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/debug/seed_connect.dart';
import '../../../core/debug/seed_ui.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../connect_controller.dart';
import 'viewfinder_overlay.dart';

class ScannerPane extends StatelessWidget {
  const ScannerPane({super.key, required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final maxHeight = AppSheetScope.maybeMaxBodyHeight(context) ?? 0;
    return SizedBox(
      height: maxHeight < AppSpacing.scannerMinPaneHeight
          ? AppSpacing.scannerMinPaneHeight + (kDebugMode ? AppSpacing.connectDebugExtra : 0)
          : maxHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth
              .clamp(AppSpacing.scannerMinSize, AppSpacing.scannerMaxSize)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.lg),
                    ),
                    child: Obx(() {
                      final state = c.cameraState.value;
                      if (state == ConnectCameraState.denied ||
                          state == ConnectCameraState.unavailable) {
                        return _CameraProblem(
                          controller: c,
                          isDenied: state == ConnectCameraState.denied,
                        );
                      }
                      return _Preview(controller: c);
                    }),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Point the camera at a Connectum QR code',
                style: AppText.readable,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: AppSpacing.minTapTarget,
                child: Obx(
                  () => c.hasTorch.value
                      ? _TorchButton(
                          isOn: c.isTorchOn.value,
                          onTap: c.toggleTorch,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              const Spacer(),
              AppButton.secondary(
                label: 'Enter code manually',
                icon: Icons.keyboard_outlined,
                onPressed: c.showManual,
              ),
              if (kDebugMode) ...[
                const SizedBox(height: AppSpacing.sm),
                _SimulateScan(controller: c),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ColoredBox(
      color: AppColors.scrim,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Obx(() {
            final camera = c.camera.value;
            final isReady = c.cameraState.value == ConnectCameraState.ready;
            if (camera == null) return const SizedBox.shrink();
            return AnimatedOpacity(
              opacity: isReady ? 1 : 0,
              duration: AppDurations.fast,
              child: MobileScanner(
                controller: camera,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => const SizedBox.shrink(),
                errorBuilder: (_, _) => const SizedBox.shrink(),
              ),
            );
          }),
          Obx(
            () => ViewfinderOverlay(
              isScanning: c.cameraState.value == ConnectCameraState.ready,
              isSuccess: c.isScanSuccess.value,
            ),
          ),
          Obx(
            () => c.cameraState.value == ConnectCameraState.starting
                ? const Align(
                    alignment: Alignment(0, 0.82),
                    child: Text(
                      'Starting camera…',
                      style: TextStyle(
                        fontFamily: AppText.fontFamily,
                        fontSize: AppText.sizeReadable,
                        color: AppColors.taupe,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Obx(() {
              final notice = c.scanNotice.value;
              return AnimatedSwitcher(
                duration: AppDurations.fast,
                child: notice == null
                    ? const SizedBox(key: ValueKey('none'))
                    : Container(
                        key: const ValueKey('notice'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: AppRadius.mdAll,
                        ),
                        child: Text(
                          notice,
                          textAlign: TextAlign.center,
                          style: AppText.readable.copyWith(
                            color: AppColors.background,
                          ),
                        ),
                      ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.isOn, required this.onTap});

  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isOn ? 'Turn torch off' : 'Turn torch on',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: AppSpacing.minTapTarget,
          height: AppSpacing.minTapTarget,
          child: Center(
            child: AnimatedContainer(
              duration: AppDurations.fast,
              width: AppSpacing.avatarSmall,
              height: AppSpacing.avatarSmall,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOn
                    ? AppColors.accent
                    : AppColors.scrim.withValues(alpha: 0.6),
              ),
              child: Icon(
                isOn ? Icons.flash_on : Icons.flash_off,
                size: 20,
                color: AppColors.background,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.controller, required this.isDenied});

  final ConnectController controller;
  final bool isDenied;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ColoredBox(
      color: AppColors.sage,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 32,
              color: AppColors.muted,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isDenied ? 'Camera access is off' : "The camera isn't available",
              style: AppText.subtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              isDenied
                  ? 'Allow the camera in Settings to scan, or enter the code by hand.'
                  : 'You can still join by entering the code by hand.',
              style: AppText.readable,
              textAlign: TextAlign.center,
            ),
            if (isDenied) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton.text(
                label: 'Open settings',
                tone: AppTextButtonTone.accent,
                onPressed: c.openSettings,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Debug builds only: feeds raw text to the parser as if it were scanned.
class _SimulateScan extends StatelessWidget {
  const _SimulateScan({required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (!SeedUi.isActive) {
      return AppButton.text(
        label: 'Simulate scan (Y2NHGHP6)',
        onPressed: () => c.handleScan('https://connectum.app/connect/Y2NHGHP6'),
      );
    }
    return SizedBox(
      height: AppSpacing.minTapTarget - AppSpacing.xxs * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: SeedConnect.presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) {
          final (label, raw) = SeedConnect.presets[i];
          return GestureDetector(
            onTap: () => c.handleScan(raw),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                borderRadius: AppRadius.pillAll,
                border: Border.all(color: AppColors.inputBorder),
              ),
              child: Text(label, style: AppText.readableStrong),
            ),
          );
        },
      ),
    );
  }
}
