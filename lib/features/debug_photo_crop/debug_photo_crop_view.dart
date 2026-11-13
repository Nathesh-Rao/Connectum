import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_pill_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import 'debug_photo_crop_controller.dart';
import '../../demo/sample_photos.dart';

class DebugPhotoCropView extends GetView<DebugPhotoCropController> {
  const DebugPhotoCropView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          const Text('Photo crop', style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Opens the real crop screen on a drawn sample. Drag, pinch, turn, '
            'straighten, zoom; Done shows the saved PNG below.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => AppPillBar(
              pills: [
                for (final s in SamplePhoto.values) AppPill(label: s.label),
              ],
              selected: c.sample.value.index,
              onSelected: (i) => c.sample.value = SamplePhoto.values[i],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => AppButton.primary(
              label: 'Open crop screen',
              isCentered: true,
              isLoading: c.isOpening.value,
              onPressed: c.open,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(() {
            final out = c.result.value;
            if (out == null) {
              return Text(
                'No result yet.',
                style: AppText.readable.copyWith(color: AppColors.muted),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Result: ${out.length} bytes, PNG, 512 x 512',
                  style: AppText.readableStrong,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Image.memory(out, width: 160, height: 160),
                    const SizedBox(width: AppSpacing.md),
                    ClipOval(child: Image.memory(out, width: 72, height: 72)),
                    const SizedBox(width: AppSpacing.md),
                    ClipOval(
                      child: Image.memory(
                        out,
                        width: AppSpacing.avatar,
                        height: AppSpacing.avatar,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
