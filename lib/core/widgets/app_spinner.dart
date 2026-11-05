import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum AppSpinnerSize {
  small(AppSpacing.spinnerSmall),
  medium(AppSpacing.spinnerMedium);

  const AppSpinnerSize(this.radius);

  final double radius;
}

/// The small or inline loading indicator, orange by default. Pass [color] on a
/// surface where orange would be invisible. Full pages use AppLoading.
class AppSpinner extends StatelessWidget {
  const AppSpinner({
    super.key,
    this.size = AppSpinnerSize.small,
    this.color = AppColors.accent,
  });

  const AppSpinner.medium({super.key, this.color = AppColors.accent})
    : size = AppSpinnerSize.medium;

  final AppSpinnerSize size;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    excludeSemantics: true,
    child: CupertinoActivityIndicator(radius: size.radius, color: color),
  );
}
