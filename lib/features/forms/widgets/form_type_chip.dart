import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// A small quiet icon naming a field's type, shown in a read-only field.
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

  static const _icons = {
    'text': Icons.title,
    'number': Icons.tag,
    'wholenumber': Icons.pin_outlined,
    'date': Icons.calendar_today_outlined,
    'time': Icons.schedule,
    'list': Icons.expand_more,
    'selection': Icons.list,
    'email': Icons.mail_outline,
    'url': Icons.link,
    'mobile': Icons.phone_outlined,
    'location': Icons.place_outlined,
    'payment': Icons.account_balance_wallet_outlined,
    'barcode': Icons.qr_code_2,
    'toggle': Icons.toggle_on_outlined,
    'file': Icons.attach_file,
    'slot': Icons.event_outlined,
    'autogenerate': Icons.auto_awesome_outlined,
    'fill': Icons.auto_fix_high,
  };

  static IconData iconOf(String type) => _icons[type] ?? Icons.title;

  @override
  Widget build(BuildContext context) {
    final name = nameOf(type);
    return Tooltip(
      message: name,
      child: Semantics(
        label: name,
        excludeSemantics: true,
        child: Container(
          width: AppSpacing.xl,
          height: AppSpacing.xl,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Icon(
            iconOf(type),
            size: AppSpacing.md,
            color: AppColors.muted,
          ),
        ),
      ),
    );
  }
}
