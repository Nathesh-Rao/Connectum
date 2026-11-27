import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../animated_callout_menu.dart';

/// One row of the callout, [height] high (measured by the geometry). A row
/// that is off shows the reason under its label and does nothing; a note has
/// no icon and no tap. [dividerAlpha] draws the inset hairline above the row
/// once the cards are one panel.
class CalloutRow extends StatelessWidget {
  const CalloutRow({
    super.key,
    required this.item,
    required this.height,
    required this.onTap,
    this.dividerAlpha = 0,
  });

  final MenuItem<Object?> item;
  final double height;
  final VoidCallback onTap;
  final double dividerAlpha;

  @override
  Widget build(BuildContext context) {
    final icon = item.icon;
    final isNote = icon == null;
    final ink = item.isDanger
        ? AppColors.error
        : item.isEnabled
        ? AppColors.ink
        : AppColors.disabledInk;
    final iconInk = item.isDanger
        ? AppColors.error
        : item.isEnabled
        ? AppColors.muted
        : AppColors.disabledInk;
    final tap = item.isEnabled && !isNote ? onTap : null;
    final content = SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.compactMenuPadding,
          vertical: isNote ? AppSpacing.sm : AppSpacing.xxs,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              SizedBox(
                width: AppSpacing.compactMenuIconSlot,
                child: Icon(
                  icon,
                  size: AppSpacing.compactMenuIcon,
                  color: iconInk,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: AppText.menuItem.copyWith(color: ink),
                  ),
                  if (item.why.isNotEmpty)
                    Text(item.why, style: AppText.caption.copyWith(color: ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      button: !isNote,
      enabled: isNote ? null : item.isEnabled,
      label: item.why.isEmpty ? item.label : '${item.label}. ${item.why}',
      excludeSemantics: true,
      onTap: tap,
      child: Stack(
        children: [
          InkWell(
            onTap: tap,
            highlightColor: AppColors.fill,
            splashColor: AppColors.fill,
            child: content,
          ),
          if (item.hasDividerAbove && dividerAlpha > 0.01)
            Positioned(
              left: AppSpacing.compactMenuPadding,
              right: AppSpacing.compactMenuPadding,
              top: 0,
              child: IgnorePointer(
                child: Divider(
                  height: 1,
                  color: AppColors.cardLine.withValues(
                    alpha: dividerAlpha.clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
