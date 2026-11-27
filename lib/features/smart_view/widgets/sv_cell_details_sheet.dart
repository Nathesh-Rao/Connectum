import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';

/// A table cell's whole value: the field's label, the text wrapped and
/// selectable, and Copy. Opened by "View more" or a long press on a cell.
class SvCellDetailsSheet {
  SvCellDetailsSheet._();

  static Future<void> show(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    return AppBottomSheet.show<void>(
      context,
      title: 'Details',
      child: SvCellDetails(label: label, value: value),
    );
  }
}

class SvCellDetails extends StatelessWidget {
  const SvCellDetails({super.key, required this.label, required this.value});

  final String label;
  final String value;

  static Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    fireAndLog(
      'sv_cell_details_sheet',
      () async => HapticFeedback.lightImpact(),
    );
    AppNotices.success('Copied');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppSv.fieldKey),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppSv.filterCardFill,
            borderRadius: BorderRadius.circular(AppSv.cardRadius - 4),
          ),
          child: SelectableText(value, style: AppText.body),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.primary(
          label: 'Copy',
          icon: Icons.copy_rounded,
          onPressed: () => copy(value),
        ),
      ],
    );
  }
}
