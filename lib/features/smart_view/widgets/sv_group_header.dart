import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../../../data/smart_view/engine/sv_engine.dart';

/// A group's header line: chevron, the group value, its row count and, when
/// the structure has a number column, the total of the first one. Tap folds
/// or opens the group; deeper levels are indented.
class SvGroupHeader extends StatelessWidget {
  const SvGroupHeader({
    super.key,
    required this.line,
    required this.sumLabel,
    required this.onTap,
  });

  final SvFlat line;
  final String? sumLabel;
  final VoidCallback onTap;

  static String number(num n) {
    final fixed = n == n.roundToDouble()
        ? n.toInt().toString()
        : n.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    final parts = fixed.split('.');
    final digits = parts[0];
    final neg = digits.startsWith('-');
    final body = neg ? digits.substring(1) : digits;
    final grouped = body.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${neg ? '-' : ''}$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = line.open ?? true;
    return Semantics(
      button: true,
      expanded: isOpen,
      label: '${line.group}, ${line.count} records',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: AppSv.groupHeaderHeight,
          padding: EdgeInsets.only(
            left: AppSv.groupIndentBase + line.depth * AppSv.groupIndentStep,
            right: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            color: AppColors.fill,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: isOpen ? 0.25 : 0,
                duration: AppDurations.smartChip,
                curve: AppCurves.out,
                child: const Icon(
                  Icons.chevron_right,
                  size: AppSpacing.popupMenuIcon,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  line.group!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.readableStrong,
                ),
              ),
              Text(
                number(line.count!),
                style: AppText.readableStrong.copyWith(
                  color: AppColors.violetStrong,
                ),
              ),
              if (sumLabel != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '$sumLabel ${number(line.sum!)}',
                  style: AppText.caption.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
