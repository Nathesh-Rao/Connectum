import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/e2e/e2e_models.dart';
import '../../../data/e2e/e2e_texts.dart';

/// The facts a device card shows, worked out from the server's record.
class DeviceFacts {
  DeviceFacts._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  static bool isPhone(E2eDevicePublic d) {
    final l = d.label.toLowerCase();
    return l.contains('mobile') ||
        l.contains('phone') ||
        l.contains('android') ||
        l.contains('ios');
  }

  static String kind(E2eDevicePublic d) => isPhone(d) ? 'Phone app' : 'Browser';

  /// When the device was last used: the server's `seen`, else when it was added.
  static int lastUsed(E2eDevicePublic d) => d.seen > 0 ? d.seen : d.ts;

  static String added(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    return 'Added ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  /// Least recently used first, so devices nobody uses come first.
  static List<E2eDevicePublic> staleFirst(Iterable<E2eDevicePublic> devices) =>
      [...devices]..sort((a, b) => lastUsed(a).compareTo(lastUsed(b)));
}

/// One registered device as a card: kind icon, name, kind and date added,
/// "Last used ...", a "This phone" chip, and a trash icon button when [hasRemove] (a null
/// [onRemove] then shows it disabled).
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.isThisPhone,
    required this.onRemove,
    required this.now,
    this.hasRemove = true,
    this.isBusy = false,
  });

  final E2eDevicePublic device;
  final bool hasRemove;
  final bool isThisPhone;
  final VoidCallback? onRemove;
  final DateTime now;
  final bool isBusy;

  static const double _removeTarget = 48;

  @override
  Widget build(BuildContext context) {
    final added = DeviceFacts.added(device.ts);
    final name = device.label.isEmpty ? 'Unnamed device' : device.label;
    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        right: AppSpacing.xs,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.avatarSmall,
            height: AppSpacing.avatarSmall,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(
              DeviceFacts.isPhone(device) ? Icons.smartphone : Icons.laptop_mac,
              size: 18,
              color: AppColors.primaryBright,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.readableStrong),
                if (isThisPhone) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  const AppTag(
                    label: E2eTexts.thisPhone,
                    tone: AppTagTone.accent,
                  ),
                ],
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Last used ${E2eTexts.ago(DeviceFacts.lastUsed(device), now)}',
                  style: AppText.caption,
                ),
                Text(
                  added.isEmpty
                      ? DeviceFacts.kind(device)
                      : '${DeviceFacts.kind(device)} · $added',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          if (!hasRemove)
            const SizedBox(width: AppSpacing.sm)
          else
            Semantics(
              button: true,
              enabled: onRemove != null && !isBusy,
              label: 'Remove $name',
              excludeSemantics: true,
              child: IconButton(
                tooltip: 'Remove $name',
                constraints: const BoxConstraints.tightFor(
                  width: _removeTarget,
                  height: _removeTarget,
                ),
                padding: EdgeInsets.zero,
                onPressed: isBusy ? null : onRemove,
                icon: isBusy
                    ? const AppSpinner(size: AppSpinnerSize.sm)
                    : const Icon(
                        Icons.delete_outline,
                        size: 22,
                        color: AppColors.error,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cards for a list of devices, least recently used first. This phone's own
/// entry has no Remove unless [canRemoveThisPhone]; with [onRemove] null the
/// others show it disabled.
class DeviceCardList extends StatelessWidget {
  const DeviceCardList({
    super.key,
    required this.devices,
    required this.isThisPhone,
    required this.onRemove,
    this.canRemoveThisPhone = false,
    this.busyId,
  });

  final List<E2eDevicePublic> devices;
  final bool Function(E2eDevicePublic) isThisPhone;
  final void Function(E2eDevicePublic)? onRemove;
  final bool canRemoveThisPhone;
  final String? busyId;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sorted = DeviceFacts.staleFirst(devices);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sorted.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          DeviceCard(
            device: sorted[i],
            isThisPhone: isThisPhone(sorted[i]),
            now: now,
            isBusy: busyId == sorted[i].id,
            hasRemove: canRemoveThisPhone || !isThisPhone(sorted[i]),
            onRemove: onRemove == null ? null : () => onRemove!(sorted[i]),
          ),
        ],
      ],
    );
  }
}
