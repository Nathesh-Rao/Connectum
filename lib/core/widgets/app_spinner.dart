import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_spacing.dart';

/// xs inside small inline text, sm inside buttons, md for paging footers and
/// inline loading rows, lg for the refresh header and small card loading.
enum AppSpinnerSize {
  xs(AppSpacing.spinnerXs),
  sm(AppSpacing.spinnerSm),
  md(AppSpacing.spinnerMd),
  lg(AppSpacing.spinnerLg);

  const AppSpinnerSize(this.extent);

  final double extent;
}

/// The small or inline loading animation, in the file's own colours. Full pages
/// use AppLoading.
class AppSpinner extends StatelessWidget {
  const AppSpinner({
    super.key,
    this.size = AppSpinnerSize.md,
    this.isStandalone = false,
  });

  static const asset = 'assets/lottie/loading_circle.json';

  /// The ring fills half of the 300 x 300 canvas, so the animation is drawn at
  /// twice the slot and clipped to it.
  static const _artworkScale = 2.0;

  final AppSpinnerSize size;

  /// Whether the spinner is the only loading hint, so it keeps its label.
  final bool isStandalone;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    excludeSemantics: !isStandalone,
    child: SizedBox(
      width: size.extent,
      height: size.extent,
      child: ClipRect(
        child: OverflowBox(
          minWidth: size.extent * _artworkScale,
          maxWidth: size.extent * _artworkScale,
          minHeight: size.extent * _artworkScale,
          maxHeight: size.extent * _artworkScale,
          child: Lottie.asset(
            asset,
            width: size.extent * _artworkScale,
            height: size.extent * _artworkScale,
            repeat: true,
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      ),
    ),
  );
}
