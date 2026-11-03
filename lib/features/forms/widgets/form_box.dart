import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';

/// A tappable box in the look of a text field, for a value picked rather than
/// typed.
class FormBox extends StatelessWidget {
  const FormBox({
    super.key,
    required this.child,
    this.onTap,
    this.trailing,
    this.error,
    this.isReadOnly = false,
    this.link,
    this.boxKey,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  final RxnString? error;
  final bool isReadOnly;
  final LayerLink? link;
  final Key? boxKey;

  Widget _box(bool hasError) {
    final box = Container(
      key: boxKey,
      constraints: const BoxConstraints(minHeight: AppSpacing.controlHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.controlPaddingX,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isReadOnly ? AppColors.sage : AppColors.background,
        borderRadius: AppRadius.controlAll,
        border: Border.all(
          color: hasError
              ? AppColors.error
              : isReadOnly
              ? AppColors.line
              : AppColors.inputBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(child: child),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );
    final anchored = link == null
        ? box
        : CompositedTransformTarget(link: link!, child: box);
    return isReadOnly
        ? Semantics(
            container: true,
            readOnly: true,
            hint: 'Read only',
            child: anchored,
          )
        : anchored;
  }

  @override
  Widget build(BuildContext context) {
    final e = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: e == null
              ? _box(false)
              : Obx(() => _box(e.value != null && e.value!.isNotEmpty)),
        ),
        if (e != null)
          Obx(
            () => AnimatedSize(
              duration: AppDurations.fast,
              curve: AppCurves.out,
              alignment: Alignment.topLeft,
              child: e.value == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(e.value!, style: AppText.error),
                    ),
            ),
          ),
      ],
    );
  }
}
