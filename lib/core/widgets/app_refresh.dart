import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Pull to refresh for a list of slivers. The orange Cupertino spinner follows
/// the drag, and bouncing physics make it pull on Android and on short lists.
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
        onRefresh: onRefresh,
        builder: (context, mode, pulled, trigger, extent) {
          final progress = (pulled / trigger).clamp(0.0, 1.0);
          return Center(
            child: mode == RefreshIndicatorMode.drag
                ? CupertinoActivityIndicator.partiallyRevealed(
                    radius: AppSpacing.spinnerMedium,
                    color: AppColors.accent,
                    progress: progress,
                  )
                : const CupertinoActivityIndicator(
                    radius: AppSpacing.spinnerMedium,
                    color: AppColors.accent,
                  ),
          );
        },
      ),
      ...slivers,
    ],
  );
}
