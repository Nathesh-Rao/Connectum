import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';

/// The auth pages' footer: "From the [Agile logo] Agile Labs Suite", centred.
/// The logo keeps its own colours (a brand mark, never tinted).
class AppAgileFooter extends StatelessWidget {
  const AppAgileFooter({super.key});

  static const logoAsset = 'assets/icons/agile/agile_logo.png';
  static const semanticLabel = 'From the Agile Labs Suite';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: Text.rich(
            TextSpan(
              style: AppText.caption,
              children: [
                const TextSpan(text: 'From the'),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Image.asset(
                      logoAsset,
                      key: const ValueKey('agile-logo'),
                      height: AppSpacing.agileLogoHeight,
                      width: AppSpacing.agileLogoHeight,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const TextSpan(text: 'Agile Labs Suite'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
