import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final Iterable<String>? autofillHints;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  static const _lineHeight = AppText.sizeBody * AppText.heightControl;
  static const _singleLinePadding =
      (AppSpacing.controlHeight - 2 - _lineHeight) / 2;

  bool _isFocused = false;

  bool get _hasError =>
      widget.errorText != null && widget.errorText!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final borderColor = _hasError
        ? AppColors.error
        : _isFocused
        ? AppColors.accent
        : AppColors.inputBorder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: AppText.label),
          const SizedBox(height: AppSpacing.xs),
        ],
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (value) => setState(() => _isFocused = value),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppCurves.out,
            constraints: const BoxConstraints(
              minHeight: AppSpacing.controlHeight,
            ),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: borderColor),
              boxShadow: _isFocused && !_hasError ? AppShadows.focusRing : null,
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              inputFormatters: widget.inputFormatters,
              autofillHints: widget.autofillHints,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              maxLength: widget.maxLength,
              textAlignVertical: TextAlignVertical.center,
              style: AppText.input,
              strutStyle: const StrutStyle(
                fontFamily: AppText.fontFamily,
                fontSize: AppText.sizeBody,
                height: AppText.heightControl,
                forceStrutHeight: true,
              ),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppText.input.copyWith(color: AppColors.muted),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.controlPaddingX,
                  vertical: _singleLinePadding,
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: AppDurations.fast,
          curve: AppCurves.out,
          alignment: Alignment.topLeft,
          child: _hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(widget.errorText!, style: AppText.error),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
