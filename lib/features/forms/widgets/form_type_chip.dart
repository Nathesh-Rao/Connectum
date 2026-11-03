import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';

/// A small quiet label naming a field's type, shown in a read-only field.
class FormTypeChip extends StatelessWidget {
  const FormTypeChip({super.key, required this.type});

  final String type;

  static const _names = {
    'text': 'Text',
    'number': 'Number',
    'wholenumber': 'Whole number',
    'date': 'Date',
    'time': 'Time',
    'list': 'List',
    'selection': 'List',
    'email': 'Email',
    'url': 'Link',
    'mobile': 'Mobile',
    'location': 'Location',
    'payment': 'Payment',
    'barcode': 'Barcode',
    'toggle': 'Yes / No',
    'file': 'File',
    'slot': 'Slot',
    'autogenerate': 'Generated',
    'fill': 'Auto',
  };

  static String nameOf(String type) => _names[type] ?? 'Text';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Text(nameOf(type), style: AppText.label),
    );
  }
}
