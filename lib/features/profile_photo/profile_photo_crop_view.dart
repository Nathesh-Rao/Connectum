import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_spinner.dart';
import 'crop_math.dart';
import 'profile_photo_crop_controller.dart';
import 'widgets/crop_stage.dart';

class ProfilePhotoCropView extends GetView<ProfilePhotoCropController> {
  const ProfilePhotoCropView({super.key});

  static const _maxBox = 360.0;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      isScrollable: false,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
            const Text('Adjust your photo', style: AppText.heading),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Drag and pinch to choose the part you want.',
              style: AppText.readable.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: Obx(() {
                if (c.hasLoadFailed.value && c.photo.value == null) {
                  return _LoadFailed(onRetry: c.load, onCancel: c.cancel);
                }
                return _Editor(controller: c);
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.controller});

  final ProfilePhotoCropController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = math.min(
          constraints.maxWidth,
          math.min(ProfilePhotoCropView._maxBox, constraints.maxHeight * 0.5),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => c.setBox(box));
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: AppRadius.cardAll,
                      child: SizedBox.square(
                        dimension: box,
                        child: ColoredBox(
                          color: AppColors.ink,
                          child: Obx(() {
                            final photo = c.photo.value;
                            final state = c.crop.value;
                            if (photo == null || state == null) {
                              return const Center(
                                child: AppSpinner(
                                  size: AppSpinnerSize.lg,
                                  color: AppColors.white,
                                  isStandalone: true,
                                ),
                              );
                            }
                            return GestureDetector(
                              onScaleStart: c.onScaleStart,
                              onScaleUpdate: c.onScaleUpdate,
                              onScaleEnd: c.onScaleEnd,
                              child: RepaintBoundary(
                                child: CropStage(
                                  photo: photo.image,
                                  state: state,
                                  isMoving: c.isMoving.value,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton.secondary(
                          label: 'Rotate left',
                          leadingIcon: Icons.rotate_90_degrees_ccw_outlined,
                          onPressed: () => c.rotate(-1),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: AppButton.secondary(
                          label: 'Rotate right',
                          leadingIcon: Icons.rotate_90_degrees_cw_outlined,
                          onPressed: () => c.rotate(1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Obx(() {
                    c.crop.value;
                    return _SliderRow(
                      label: 'Straighten',
                      value: '${c.straightenDegrees.round()}°',
                      slider: _CropSlider(
                        value: c.straightenDegrees,
                        min: -45,
                        max: 45,
                        onChanged: c.setStraighten,
                      ),
                      onReset: c.straightenDegrees == 0
                          ? null
                          : () => c.setStraighten(0),
                    );
                  }),
                  Obx(() {
                    c.crop.value;
                    return _SliderRow(
                      label: 'Zoom',
                      value:
                          '${(1 + c.zoomSlider * (CropState.maxZoom - 1)).toStringAsFixed(1)}×',
                      slider: _CropSlider(
                        value: c.zoomSlider,
                        min: 0,
                        max: 1,
                        onChanged: c.setZoomSlider,
                      ),
                    );
                  }),
                  if (c.isDebug) Obx(() => _DebugReadout(state: c.crop.value)),
                  const Spacer(),
                  const SizedBox(height: AppSpacing.sm),
                  Obx(
                    () => AppButton.text(
                      label: 'Reset',
                      tone: AppTextButtonTone.ink,
                      onPressed: c.canReset && !c.isRendering.value
                          ? c.reset
                          : null,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton.secondary(
                          label: 'Cancel',
                          onPressed: c.cancel,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Obx(
                          () => AppButton.primary(
                            label: 'Done',
                            isCentered: true,
                            isLoading: c.isRendering.value,
                            onPressed: c.crop.value == null ? null : c.done,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
    this.onReset,
  });

  final String label;
  final String value;
  final Widget slider;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(label, style: AppText.readableStrong),
          const SizedBox(width: AppSpacing.xs),
          Text(value, style: AppText.readable.copyWith(color: AppColors.muted)),
          const Spacer(),
          if (onReset != null)
            GestureDetector(
              onTap: onReset,
              behavior: HitTestBehavior.opaque,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTapTarget,
                ),
                child: Center(
                  child: Text(
                    'Reset',
                    style: AppText.readableStrong.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      slider,
    ],
  );
}

class _CropSlider extends StatelessWidget {
  const _CropSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => SliderTheme(
    data: SliderTheme.of(context).copyWith(
      trackHeight: AppSpacing.progressHeight,
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.line,
      thumbColor: AppColors.primary,
      overlayColor: AppColors.primary.withValues(alpha: 0.12),
    ),
    child: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      onChanged: onChanged,
    ),
  );
}

class _DebugReadout extends StatelessWidget {
  const _DebugReadout({required this.state});

  final CropState? state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null) return const SizedBox.shrink();
    final r = s.sourceRect;
    return Text(
      'angle ${(s.angle * 180 / math.pi).toStringAsFixed(1)}°  '
      'zoom ${s.zoom.toStringAsFixed(2)}  scale ${s.scale.toStringAsFixed(3)}\n'
      'source ${r.left.round()},${r.top.round()}  '
      '${r.width.round()} x ${r.height.round()}  of ${s.imageW.round()} x ${s.imageH.round()}',
      style: AppText.readable.copyWith(color: AppColors.muted),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry, required this.onCancel});

  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        "This photo couldn't be opened. Try another one.",
        textAlign: TextAlign.center,
        style: AppText.body.copyWith(color: AppColors.muted),
      ),
      const SizedBox(height: AppSpacing.lg),
      AppButton.secondary(label: 'Try again', onPressed: onRetry),
      const SizedBox(height: AppSpacing.xs),
      AppButton.text(
        label: 'Cancel',
        tone: AppTextButtonTone.ink,
        onPressed: onCancel,
      ),
    ],
  );
}
