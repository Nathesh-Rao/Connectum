import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/e2e/e2e_models.dart';

/// One registered device: label, short id, date added, and Remove.
class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.device,
    required this.isThisPhone,
    required this.onRemove,
    this.isBusy = false,
    this.hasDivider = true,
  });

  final E2eDevicePublic device;
  final bool isThisPhone;
  final VoidCallback? onRemove;
  final bool isBusy;
  final bool hasDivider;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  static String added(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return 'Added ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final id = device.id.length > 8 ? device.id.substring(0, 8) : device.id;
    final date = added(device.ts);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        border: hasDivider
            ? const Border(top: BorderSide(color: AppColors.line))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.label.isEmpty ? 'Unnamed device' : device.label,
                  style: AppText.readableStrong,
                ),
                if (isThisPhone)
                  Text(
                    'This phone',
                    style: AppText.caption.copyWith(color: AppColors.accentInk),
                  ),
                Text(
                  date.isEmpty ? 'ID $id' : 'ID $id · $date',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          AppButton.text(
            label: 'Remove',
            tone: AppTextButtonTone.accent,
            isLoading: isBusy,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
