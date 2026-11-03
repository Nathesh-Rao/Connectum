import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/form_option.dart';
import '../../../data/models/ids.dart';
import '../form_controller.dart';
import '../form_rules.dart';
import '../models/field_input.dart';
import '../form_formats.dart';
import 'barcode_scanner_sheet.dart';
import 'form_choice_menu.dart';
import 'form_box.dart';
import 'form_file_field.dart';
import 'form_payment_field.dart';
import 'form_slot_field.dart';
import 'form_type_chip.dart';

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
          Obx(
            () => input.isStaleChoices.value
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxs),
                    child: Text(
                      'May be out of date',
                      style: AppText.caption.copyWith(color: AppColors.muted),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _control(BuildContext context) {
    final f = input.def;
    if (!FormRules.isSupported(f) && !f.hasCalc) {
      return FormBox(
        error: input.error,
        trailing: const Icon(
          Icons.lock_outline,
          size: 16,
          color: AppColors.muted,
        ),
        child: Text(
          'Supported in the next update',
          style: AppText.input.copyWith(color: AppColors.muted),
        ),
      );
    }
    if (f.hasCalc || f.isReadOnly && f.type != 'autogenerate') {
      return FormBox(
        error: input.error,
        isReadOnly: true,
        trailing: FormTypeChip(type: f.type),
        child: Obx(() => _valueText(_shown(input.value.value))),
      );
    }
    return switch (f.type) {
      'autogenerate' => FormBox(
        isReadOnly: true,
        trailing: FormTypeChip(type: f.type),
        child: Obx(() {
          final saved = idText(input.value.value);
          return Text(
            saved.isEmpty ? 'Generated when saved' : saved,
            style: _readOnlyStyle,
          );
        }),
      ),
      'fill' => FormBox(
        error: input.error,
        isReadOnly: true,
        trailing: FormTypeChip(type: f.type),
        child: Obx(() {
          final v = idText(input.value.value);
          return Text(
            v.isEmpty ? 'Filled in automatically' : v,
            style: _readOnlyStyle,
          );
        }),
      ),
      'toggle' => _toggle(),
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
      'selection' =>
        _hasSource ? _list(context) : _typed(helper: 'Type the value.'),
      'barcode' => _typed(
        suffix: IconButton(
          tooltip: 'Scan a code',
          onPressed: () => _scan(context),
          icon: const Icon(
            Icons.qr_code_scanner,
            size: 20,
            color: AppColors.muted,
          ),
        ),
      ),
      'location' => _typed(
        hint: 'Latitude, longitude (12.97, 77.59)',
        helper: 'Type the place as two numbers.',
      ),
      'payment' => FormPaymentField(
        controller: controller,
        input: input,
        row: row,
      ),
      'file' => FormFileField(controller: controller, input: input),
      'slot' => FormSlotField(controller: controller, input: input, row: row),
      _ => _typed(),
    };
  }

  bool get _hasSource => input.def.raw['source'] is Map;

  /// The text shown for a held value that is not plain text.
  String _mapShown(Map v) {
    final f = input.def;
    if (f.type == 'payment') {
      final currency = idText(f.raw['currency']);
      return [
        if (idText(v['amount']).isNotEmpty)
          '$currency ${idText(v['amount'])}'.trim(),
        if (idText(v['status']) == 'paid') 'Paid' else 'Pay later',
        if (idText(v['method']).isNotEmpty) idText(v['method']),
      ].join(' · ');
    }
    final lat = idText(v['lat']);
    final lng = idText(v['lng']);
    return lat.isEmpty || lng.isEmpty ? '' : '$lat, $lng';
  }

  /// A held value as the person reads it: dates in the form's format, a
  /// list's choice by its label.
  String _shown(Object? v) {
    final f = input.def;
    if (v is Map) return _mapShown(v);
    if (f.type == 'file' && v is List) {
      return v.length == 1 ? '1 file' : '${v.length} files';
    }
    if (v is List) {
      final labels = input.choices.value;
      return v
          .map(
            (e) =>
                labels?.where((c) => c.value == idText(e)).firstOrNull?.label ??
                idText(e),
          )
          .join(', ');
    }
    final text = idText(v);
    if (f.type == 'date') {
      return FormDates.show(text, isMonthFirst: controller.isMonthFirst);
    }
    if (f.type == 'list' || f.type == 'selection') {
      final hit = input.choices.value?.where((c) => c.value == text);
      if (hit != null && hit.isNotEmpty) return hit.first.label;
    }
    return text;
  }

  Widget _toggle() => Obx(() {
    final isOn = input.value.value == 'Yes';
    return FormBox(
      error: input.error,
      onTap: () => controller.setValue(input, isOn ? 'No' : 'Yes', row: row),
      trailing: IgnorePointer(
        child: Switch(
          value: isOn,
          activeThumbColor: AppColors.accent,
          onChanged: (_) {},
        ),
      ),
      child: Text(isOn ? 'Yes' : 'No', style: AppText.input),
    );
  });

  static final _readOnlyStyle = AppText.input.copyWith(
    color: AppColors.readOnlyInk,
    fontWeight: FontWeight.w600,
  );

  Widget _valueText(String text) =>
      Text(text.isEmpty ? '-' : text, style: _readOnlyStyle);

  Widget _typed({String? hint, String? helper, Widget? suffix}) {
    final c = controller;
    final f = input.def;
    final isMultiline = f.type == 'text' && f.isMultiline;
    final length = FormFormats.maxLength(f);
    return Obx(() {
      final typed = (input.value.value is String)
          ? (input.value.value as String).length
          : 0;
      final waiting = input.waitingFor.toList();
      final shownHelper =
          input.note.value ??
          (waiting.isNotEmpty
              ? 'Fills in after you choose ${waiting.join(', ')}'
              : length != null && typed >= FormFormats.counterFrom
              ? '$typed / $length'
              : helper);
      return AppTextField(
        controller: input.text,
        focusNode: input.focus,
        hint: hint,
        keyboardType: FormFormats.keyboard(f),
        inputFormatters: FormFormats.formatters(f),
        maxLength: length,
        textCapitalization: FormFormats.capitalization(f),
        autocorrect: FormFormats.hasSuggestions(f),
        minLines: isMultiline ? 4 : 1,
        maxLines: isMultiline ? 8 : 1,
        errorText: input.error.value,
        helperText: shownHelper,
        suffix: suffix,
        textInputAction: isMultiline
            ? TextInputAction.newline
            : identical(c.lastTyped, input)
            ? TextInputAction.done
            : TextInputAction.next,
        onChanged: (v) => c.setValue(input, v, row: row),
      );
    });
  }

  Future<void> _scan(BuildContext context) async {
    final code = await BarcodeScannerSheet.show(
      context,
      title: input.def.caption,
    );
    if (code == null) return;
    input.text.text = code;
    controller.setValue(input, code, row: row);
  }

  Widget _picker({
    required IconData icon,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Obx(() {
      final text = _shown(input.value.value);
      return FormBox(
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
      final choices = c.shownChoices(input, row: row);
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
      final waiting = input.waitingFor.toList();
      final hint = waiting.isNotEmpty
          ? 'Choose ${waiting.join(', ')} first'
          : isLoading
          ? 'Loading choices…'
          : failed
          ? (c.isConnectNeeded
                ? 'Connect to choose'
                : 'Needs a connection to load the choices')
          : choices != null && choices.isEmpty
          ? 'Nothing to choose from yet'
          : f.isMulti
          ? 'Pick one or more'
          : 'Select…';
      final text = labels.join(', ');
      final isUsable = choices != null && choices.isNotEmpty;
      return FormChoiceMenu(
        choices: choices ?? const [],
        selected: selected,
        isMulti: f.isMulti,
        onDone: (picked) => c.setValue(
          input,
          f.isMulti ? picked : (picked.isEmpty ? null : picked.first),
          row: row,
        ),
        builder: (link, boxKey, open) => FormBox(
          error: input.error,
          link: link,
          boxKey: boxKey,
          onTap: isUsable
              ? open
              : (failed && !c.isConnectNeeded
                    ? () => f.type == 'selection'
                          ? c.retrySelection(input, row: row)
                          : c.retryChoices(input)
                    : null),
          trailing: Icon(
            failed && !c.isConnectNeeded
                ? Icons.refresh
                : Icons.keyboard_arrow_down,
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
      row: row,
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
      row: row,
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }
}
