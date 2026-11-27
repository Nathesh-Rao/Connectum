import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';

/// A tappable box in the look of a text field, for a value picked rather than
/// typed.
class FormBox extends StatelessWidget {
  const FormBox({
    super.key,
    required this.child,
    this.onTap,
    this.trailing,
    this.error,
    this.errorText,
    this.isReadOnly = false,
    this.link,
    this.boxKey,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  final RxnString? error;

  /// A message that does not change with an observable (shown when [error] is null).
  final String? errorText;
  final bool isReadOnly;
  final LayerLink? link;
  final Key? boxKey;

  bool get _hasText => errorText != null && errorText!.isNotEmpty;

  Widget _box(bool hasError) {
    final box = Container(
      key: boxKey,
      constraints: const BoxConstraints(minHeight: AppSpacing.controlHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.controlPaddingX,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isReadOnly ? AppColors.fill : AppColors.white,
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
              ? _box(_hasText)
              : Obx(() => _box(e.value != null && e.value!.isNotEmpty)),
        ),
        if (e == null && _hasText)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(errorText!, style: AppText.error),
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
