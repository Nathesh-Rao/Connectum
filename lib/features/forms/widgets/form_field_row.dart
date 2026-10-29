import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/form_option.dart';
import '../../../data/models/ids.dart';
import '../form_controller.dart';
import '../models/field_input.dart';
import 'choice_sheet.dart';

/// One field: its label (with a red-orange star when required), the control
/// for its type, and its error under it. Shown only while its condition holds.
class FormFieldRow extends StatelessWidget {
  const FormFieldRow({
    super.key,
    required this.controller,
    required this.input,
    this.row,
  });

  final FormController controller;
  final FieldInput input;
  final RowInput? row;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final f = input.def;
    // A field with no condition always shows and watches nothing.
    if (!c.hasCondition(f)) return _field(context);
    return Obx(
      () =>
          c.isVisible(f, row: row) ? _field(context) : const SizedBox.shrink(),
    );
  }

  Widget _field(BuildContext context) {
    final f = input.def;
    return Padding(
      key: input.key,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text.rich(
              TextSpan(
                text: f.caption,
                children: [
                  if (f.isRequired)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: AppColors.accent),
                    ),
                ],
              ),
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
          ),
          _control(context),
        ],
      ),
    );
  }

  Widget _control(BuildContext context) {
    final f = input.def;
    if (f.hasCalc || f.isReadOnly && f.type != 'autogenerate') {
      return _Box(
        error: input.error,
        child: Obx(() => _valueText(idText(input.value.value))),
      );
    }
    return switch (f.type) {
      'autogenerate' => const _Box(
        child: Text('Assigned when it is saved', style: AppText.readable),
      ),
      'text' => _typed(
        keyboard: f.isMultiline ? TextInputType.multiline : TextInputType.text,
        lines: f.isMultiline ? 4 : 1,
      ),
      'email' => _typed(keyboard: TextInputType.emailAddress),
      'url' => _typed(keyboard: TextInputType.url),
      'mobile' => _typed(
        keyboard: TextInputType.phone,
        formatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]')),
        ],
      ),
      'wholenumber' => _typed(
        keyboard: const TextInputType.numberWithOptions(signed: true),
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
      ),
      'number' => _typed(
        keyboard: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        formatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*\.?\d*'))],
      ),
      'location' => _typed(
        keyboard: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        hint: 'Latitude, longitude (12.97, 77.59)',
        helper: 'Type the place as two numbers.',
      ),
      'date' => _picker(
        icon: Icons.calendar_today_outlined,
        hint: 'Pick a date',
        onTap: () => _pickDate(context),
      ),
      'time' => _picker(
        icon: Icons.schedule,
        hint: 'Pick a time',
        onTap: () => _pickTime(context),
      ),
      'list' => _list(context),
      _ => _Box(
        error: input.error,
        child: const Text(
          "Mobile can't fill this field yet",
          style: AppText.readable,
        ),
      ),
    };
  }

  Widget _valueText(String text) => Text(
    text.isEmpty ? '-' : text,
    style: AppText.input.copyWith(color: AppColors.muted),
  );

  Widget _typed({
    required TextInputType keyboard,
    int lines = 1,
    List<TextInputFormatter>? formatters,
    String? hint,
    String? helper,
  }) {
    final c = controller;
    return Obx(
      () => AppTextField(
        controller: input.text,
        focusNode: input.focus,
        hint: hint,
        keyboardType: keyboard,
        inputFormatters: formatters,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 8,
        errorText: input.error.value,
        helperText: helper,
        textInputAction: lines == 1
            ? TextInputAction.next
            : TextInputAction.newline,
        onChanged: (v) => c.setValue(input, v),
      ),
    );
  }

  Widget _picker({
    required IconData icon,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Obx(() {
      final text = idText(input.value.value);
      return _Box(
        error: input.error,
        onTap: onTap,
        trailing: Icon(icon, size: 18, color: AppColors.muted),
        child: Text(
          text.isEmpty ? hint : text,
          style: AppText.input.copyWith(
            color: text.isEmpty ? AppColors.muted : AppColors.ink,
          ),
        ),
      );
    });
  }

  Widget _list(BuildContext context) {
    final c = controller;
    final f = input.def;
    return Obx(() {
      final choices = input.choices.value;
      final value = input.value.value;
      final labels = <String>[];
      final selected = value is List
          ? [for (final e in value) idText(e)]
          : idText(value).isEmpty
          ? <String>[]
          : [idText(value)];
      for (final s in selected) {
        labels.add(
          choices
                  ?.firstWhere(
                    (x) => x.value == s,
                    orElse: () => FormChoice(s, s),
                  )
                  .label ??
              s,
        );
      }
      final isLoading = input.isLoadingChoices.value;
      final failed = input.hasChoicesFailed.value;
      final hint = isLoading
          ? 'Loading choices…'
          : failed
          ? 'Needs a connection to load the choices'
          : f.isMulti
          ? 'Pick one or more'
          : 'Select…';
      final text = labels.join(', ');
      return _Box(
        error: input.error,
        onTap: choices == null
            ? (failed ? () => c.retryChoices(input) : null)
            : () => ChoiceSheet.show(
                context,
                title: f.caption,
                choices: choices,
                selected: selected,
                isMulti: f.isMulti,
                onDone: (picked) => c.setValue(
                  input,
                  f.isMulti ? picked : (picked.isEmpty ? null : picked.first),
                ),
              ),
        trailing: Icon(
          failed ? Icons.refresh : Icons.keyboard_arrow_down,
          size: 20,
          color: AppColors.muted,
        ),
        child: Text(
          text.isEmpty ? hint : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.input.copyWith(
            color: text.isEmpty ? AppColors.muted : AppColors.ink,
          ),
        ),
      );
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final f = input.def;
    final current = DateTime.tryParse(idText(input.value.value));
    final min = DateTime.tryParse(f.minText) ?? DateTime(1900);
    final max = DateTime.tryParse(f.maxText) ?? DateTime(2100);
    var start = current ?? DateTime.now();
    if (start.isBefore(min)) start = min;
    if (start.isAfter(max)) start = max;
    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: min,
      lastDate: max,
    );
    if (picked == null) return;
    controller.setValue(
      input,
      '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final parts = idText(input.value.value).split(':');
    final start = parts.length >= 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts[1]) ?? 0,
          )
        : TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: start);
    if (picked == null) return;
    controller.setValue(
      input,
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }
}

/// A tappable box in the look of a text field, for a value picked rather than
/// typed.
class _Box extends StatelessWidget {
  const _Box({required this.child, this.onTap, this.trailing, this.error});

  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  final RxnString? error;

  Widget _box(bool hasError) => Container(
    constraints: const BoxConstraints(minHeight: AppSpacing.controlHeight),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.controlPaddingX,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: AppRadius.controlAll,
      border: Border.all(
        color: hasError ? AppColors.error : AppColors.inputBorder,
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
