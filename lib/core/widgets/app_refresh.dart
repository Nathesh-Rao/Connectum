import 'package:flutter/cupertino.dart';

import '../theme/app_spacing.dart';
import 'app_spinner/app_spinner_double.dart';
import 'app_spinner/pull_refresh_config.dart';

/// Pull to refresh for a list of slivers, the Cupertino way on both platforms:
/// the content bounces, the header grows with the pull and stays pinned while
/// [onRefresh] runs. The header shows [AppSpinnerDouble]: it scales in and
/// turns with the pull, then spins freely until [onRefresh] completes.
/// This is the only place a refresh control is built.
class AppRefresh extends StatelessWidget {
  const AppRefresh({
    super.key,
    required this.onRefresh,
    required this.slivers,
    this.spinnerSize = AppSpacing.spinnerPull,
    this.spinnerColor = kPullRefreshColor,
    this.wrapSpinner,
    this.controller,
  });

  final Future<void> Function() onRefresh;
  final List<Widget> slivers;
  final double spinnerSize;
  final Color spinnerColor;

  /// For a list wider than the screen (the Smart View table): places the
  /// spinner inside the part of the list that is on screen.
  final Widget Function(Widget spinner)? wrapSpinner;

  /// The scroll position, for a page that scrolls to its top on request.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: controller,
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

  Widget _buildHeader(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) {
    final isPulling =
        mode == RefreshIndicatorMode.drag ||
        mode == RefreshIndicatorMode.armed ||
        mode == RefreshIndicatorMode.inactive;
    final isRunning =
        mode == RefreshIndicatorMode.refresh ||
        mode == RefreshIndicatorMode.done;
    final progress = isPulling
        ? (pulledExtent / refreshTriggerPullDistance).clamp(0.0, 1.0)
        : (pulledExtent / refreshIndicatorExtent).clamp(0.0, 1.0);
    final spinner = AppSpinnerDouble(
      size: spinnerSize,
      color: spinnerColor,
      progress: progress,
      spinning: isRunning,
    );
    return wrapSpinner?.call(spinner) ?? Center(child: spinner);
  }
}
