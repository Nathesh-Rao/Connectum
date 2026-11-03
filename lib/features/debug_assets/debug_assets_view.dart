import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import 'debug_assets_controller.dart';
import 'lottie_tile.dart';

class DebugAssetsView extends GetView<DebugAssetsController> {
  const DebugAssetsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => Offstage(
              offstage: c.measuring.value != null,
              child: TickerMode(
                enabled: c.measuring.value == null,
                child: _StateImages(controller: c),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Text('Lottie', style: AppText.title),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final info in c.lotties)
                  LottieTile(
                    key: ValueKey(info.name),
                    info: info,
                    controller: c,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Text('Attachment tag vectors', style: AppText.title),
          for (final (label, isOk) in c.tagResults)
            Text(
              '${isOk ? 'PASS' : 'FAIL'}  $label',
              style: AppText.caption.copyWith(
                color: isOk ? AppColors.yesText : AppColors.error,
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _StateImages extends StatelessWidget {
  const _StateImages({required this.controller});

  final DebugAssetsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('State images', style: AppText.title),
        const SizedBox(height: AppSpacing.sm),
        Obx(
          () => Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final p in controller.pngs)
                SizedBox(
                  width: 150,
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.line),
                        ),
                        child: AppStateImage(kind: p.kind, size: 150),
                      ),
                      Text(
                        '${p.kind.file}.png\n${p.width}x${p.height} - ${p.kb} KB'
                        '${p.kind.scale == 1 ? '' : ' - scale ${p.kind.scale}'}',
                        style: AppText.caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
