import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// xs inside small inline text, sm inside buttons, md for paging footers and
/// inline loading rows, lg for the refresh header and small card loading.
enum AppSpinnerSize {
  xs(AppSpacing.spinnerXs),
  sm(AppSpacing.spinnerSm),
  md(AppSpacing.spinnerMd),
  lg(AppSpacing.spinnerLg);

  const AppSpinnerSize(this.extent);

  /// The visible size of the indicator.
  final double extent;

  double get radius => extent / 2;
}

/// The small or inline loading indicator, orange by default. Pass [color] on a
/// surface where orange would be invisible. Full pages use AppLoading.
class AppSpinner extends StatelessWidget {
  const AppSpinner({
    super.key,
    this.size = AppSpinnerSize.md,
    this.color = AppColors.accent,
    this.isStandalone = false,
  });

  final AppSpinnerSize size;
  final Color color;

  /// Whether the spinner is the only loading hint, so it keeps its label.
  final bool isStandalone;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    excludeSemantics: !isStandalone,
    child: CupertinoActivityIndicator(
      radius: size.radius,
      color: color,
      animating: !MediaQuery.disableAnimationsOf(context),
    ),
  );
}
