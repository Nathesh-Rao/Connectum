import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_row_highlight.dart';

/// One rounded card that holds a run of rows, split by hairlines.
class ProfileGroup extends StatelessWidget {
  const ProfileGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxs,
            0,
            AppSpacing.xxs,
            AppSpacing.sm,
          ),
          child: Text(title, style: AppText.eyebrow),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, thickness: 1, color: AppColors.line),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A row with a label over its value, used for the account details.
class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle = AppText.body,
    this.trailing,
    this.onTap,
  });

  static const minHeight = 56.0;

  final String label;
  final String value;
  final TextStyle valueStyle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppRowHighlight(
      bleed: 0,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.rowCaption),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable row: line icon in a tint tile, title, optional caption, chevron.
class ProfileActionRow extends StatelessWidget {
  const ProfileActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: AppRowHighlight(
        bleed: 0,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ProfileInfoRow.minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.avatarSmall,
                  height: AppSpacing.avatarSmall,
                  decoration: const BoxDecoration(
                    color: AppColors.accentTint,
                    borderRadius: AppRadius.controlAll,
                  ),
                  child: Icon(icon, size: 20, color: AppColors.accentInk),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowTitle,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowCaption,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.rowChevron,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
