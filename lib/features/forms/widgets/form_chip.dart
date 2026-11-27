import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/tonal_accent.dart';

/// One form in the forms sheet: an outlined pill with a small tinted icon.
/// With no [onTap] it is the quiet "not available" kind: faded, inert.
class FormChip extends StatelessWidget {
  const FormChip({
    super.key,
    required this.label,
    required this.icon,
    required this.tintKey,
    this.onTap,
    this.semanticsLabel,
  });

  static const double height = 38;
  static const double tapHeight = 40;

  static const _accents = [
    AppColors.primary,
    AppColors.violet,
    AppColors.cyanBlue,
    AppColors.purple,
    AppColors.yesDot,
    AppColors.primaryBright,
  ];

  /// A stable accent for [key], so a form keeps its colour between opens.
  static Color accentOf(String key) {
    var h = 0;
    for (final u in key.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _accents[h % _accents.length].withAlpha(190);
  }

  static const double borderAlpha = TonalAccent.borderAlpha;

  /// The one chip look: a white fill and a 1px
  /// border in the same accent at [borderAlpha]. A null [accent] is the
  /// neutral white chip with a hairline. Flip it here.
  static BoxDecoration decoration(Color? accent) => BoxDecoration(
    color: AppColors.white,
    border: accent == null
        ? const Border.fromBorderSide(BorderSide(color: AppColors.line))
        : TonalAccent.border(accent),
    borderRadius: AppRadius.pillAll,
  );

  final String label;
  final IconData icon;
  final String tintKey;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  bool get _isEnabled => onTap != null;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      constraints: const BoxConstraints(minHeight: height),
      decoration: decoration(_isEnabled ? accentOf(tintKey) : null),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.pillAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.muted.withAlpha(24),
          highlightColor: AppColors.muted.withAlpha(14),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: _isEnabled ? accentOf(tintKey) : AppColors.muted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: _isEnabled,
      enabled: _isEnabled,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: tapHeight),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: _isEnabled ? chip : Opacity(opacity: 0.5, child: chip),
        ),
      ),
    );
  }
}
