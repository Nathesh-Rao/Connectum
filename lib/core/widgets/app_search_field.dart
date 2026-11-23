import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_text_field.dart';

/// The app's search box: filled, small corners, search icon, and a clear
/// button while there is text.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.onClear,
  });

  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Replaces the default clear (empty the field and report '').
  final VoidCallback? onClear;

  void _clear() {
    if (onClear != null) {
      onClear!();
      return;
    }
    controller.clear();
    onChanged('');
  }

  @override
  Widget build(BuildContext context) => AppTextField(
    controller: controller,
    focusNode: focusNode,
    autofocus: autofocus,
    hint: hint,
    minHeight: AppSpacing.searchHeight,
    fillColor: AppColors.searchFill,
    borderColor: Colors.transparent,
    borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xs)),
    leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
    suffix: ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => value.text.isEmpty
          ? const SizedBox.shrink()
          : AppButton.icon(
              icon: Icons.close,
              semanticLabel: 'Clear search',
              onPressed: _clear,
            ),
    ),
    textInputAction: TextInputAction.search,
    onChanged: onChanged,
  );
}
