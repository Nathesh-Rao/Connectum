import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_spinner.dart';

/// Pull to refresh for a list of slivers, the Cupertino way on both platforms:
/// the content bounces, the header grows with the pull and stays pinned while
/// [onRefresh] runs. The header shows the standard activity indicator.
class AppRefresh extends StatelessWidget {
  const AppRefresh({super.key, required this.onRefresh, required this.slivers});

  final Future<void> Function() onRefresh;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    ),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    slivers: [
      CupertinoSliverRefreshControl(
        refreshTriggerPullDistance: AppSpacing.refreshTrigger,
        refreshIndicatorExtent: AppSpacing.refreshExtent,
        onRefresh: onRefresh,
        builder: _buildHeader,
      ),
      ...slivers,
    ],
  );

  static Widget _buildHeader(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) {
    final isPulling =
        mode == RefreshIndicatorMode.drag ||
        mode == RefreshIndicatorMode.inactive;
    final radius = AppSpinnerSize.lg.radius;
    return Semantics(
      label: 'Loading',
      child: Center(
        child: isPulling
            ? CupertinoActivityIndicator.partiallyRevealed(
                radius: radius,
                color: AppColors.primaryBright,
                progress: (pulledExtent / refreshTriggerPullDistance).clamp(
                  0.0,
                  1.0,
                ),
              )
            : CupertinoActivityIndicator(
                radius: radius,
                color: AppColors.primaryBright,
              ),
      ),
    );
  }
}
