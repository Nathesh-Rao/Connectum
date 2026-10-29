import 'package:flutter/material.dart';

import '../../data/models/form_entry.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_status_pill.dart';

/// A caption with its value: the caption on the left and the value on the
/// right, or stacked when the value is long. A hairline sits above it unless
/// it is the first. [showCoordinates] adds the raw coordinates under a pinned
/// location.
class AppKeyValueRow extends StatelessWidget {
  const AppKeyValueRow({
    super.key,
    required this.entry,
    this.hasDivider = true,
    this.showCoordinates = false,
  });

  final FormEntry entry;
  final bool hasDivider;
  final bool showCoordinates;

  static const _longValue = 36;

  @override
  Widget build(BuildContext context) {
    final isLong =
        entry.text.length > _longValue ||
        entry.text.contains('\n') ||
        (entry.isLocation && entry.text.length > 22);
    final label = Text(entry.caption, style: AppText.readable);
    final value = _Value(entry: entry, showCoordinates: showCoordinates);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: hasDivider
            ? const Border(top: BorderSide(color: AppColors.line))
            : null,
      ),
      child: isLong
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: AppSpacing.xxs),
                value,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: label),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 6,
                  child: Align(alignment: Alignment.topRight, child: value),
                ),
              ],
            ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.entry, required this.showCoordinates});

  final FormEntry entry;
  final bool showCoordinates;

  @override
  Widget build(BuildContext context) {
    switch (entry.kind) {
      case FormEntryKind.yes:
      case FormEntryKind.no:
        return AppStatusPill(isYes: entry.kind == FormEntryKind.yes);
      case FormEntryKind.location:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: AppColors.ink,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(entry.text, style: AppText.readableStrong),
                ),
              ],
            ),
            if (showCoordinates && entry.coordinates != null)
              Text(entry.coordinates!, style: AppText.caption),
          ],
        );
      case FormEntryKind.text:
        return Text(entry.text, style: AppText.readableStrong);
    }
  }
}
