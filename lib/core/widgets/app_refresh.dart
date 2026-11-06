import 'package:flutter/cupertino.dart';

import '../theme/app_spacing.dart';
import 'app_spinner.dart';

/// Pull to refresh for a list of slivers, the Cupertino way on both platforms:
/// the content bounces, the header grows with the pull and stays pinned while
/// [onRefresh] runs. The Lottie ring loops in the header.
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
  ) => const Center(
    child: AppSpinner(size: AppSpinnerSize.lg, isStandalone: true),
  );
}
