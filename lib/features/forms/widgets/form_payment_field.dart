import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/ids.dart';
import '../form_controller.dart';
import '../form_formats.dart';
import '../form_rules.dart';
import '../models/field_input.dart';

/// A payment: the amount, paid now or later, and how it was paid. It records
/// what was taken or promised; no payment service is involved.
class FormPaymentField extends StatelessWidget {
  const FormPaymentField({
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
    final f = input.def;
    final currency = idText(f.raw['currency']);
    final methods = FormRules.methodsOf(f);
    return Obx(() {
      final v = input.value.value is Map ? input.value.value as Map : const {};
      final isPaid = idText(v['status']) == 'paid';
      final method = idText(v['method']).toLowerCase();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: input.text,
            focusNode: input.focus,
            hint: '0',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [AmountFormatter()],
            errorText: input.error.value,
            textInputAction: TextInputAction.done,
            leading: currency.isEmpty
                ? null
                : Text(currency, style: AppText.input),
            onChanged: (t) => controller.setPayment(input, amount: t, row: row),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _Chip(
                  label: 'Pay later',
                  isOn: !isPaid,
                  onTap: () =>
                      controller.setPayment(input, status: 'pending', row: row),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _Chip(
                  label: 'Paid now',
                  isOn: isPaid,
                  onTap: () =>
                      controller.setPayment(input, status: 'paid', row: row),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final m in methods)
                _Chip(
                  label: m,
                  isOn: method == m.toLowerCase(),
                  onTap: () => controller.setPayment(
                    input,
                    method: method == m.toLowerCase() ? '' : m,
                    row: row,
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.isOn, required this.onTap});

  final String label;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: AppSpacing.chipHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: isOn ? AppColors.accentTint : AppColors.background,
        borderRadius: AppRadius.controlAll,
        border: Border.all(
          color: isOn ? AppColors.accent : AppColors.inputBorder,
        ),
      ),
      child: Text(
        label,
        style: AppText.readable.copyWith(
          color: isOn ? AppColors.accentInk : AppColors.ink,
        ),
      ),
    ),
  );
}
