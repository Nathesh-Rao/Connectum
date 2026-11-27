import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/ai_agents/ai_agents.dart';
import 'package:connectum/features/chats/chats.dart';
import 'package:connectum/features/inbox/inbox.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'package:connectum/features/submissions/submissions.dart';
import 'home_shell_controller.dart';
import 'home_tab.dart';

class HomeShellView extends GetView<HomeShellController> {
  const HomeShellView({super.key});

  static const _screens = <Widget>[
    ChatsView(),
    SmartViewView(),
    InboxView(),
    AiAgentsView(),
    SubmissionsView(),
  ];

  /// The bar's items, in tab order (the order of [_screens]).
  static List<AppNavItem> navItems({bool hasUnread = false}) => [
    AppNavItem(
      label: 'Chats',
      selectedAsset: AppIcons.bottomNav.chatSelected,
      unselectedAsset: AppIcons.bottomNav.chatUnselected,
      showDot: hasUnread,
    ),
    AppNavItem(
      label: 'Smart view',
      selectedAsset: AppIcons.bottomNav.smartViewSelected,
      unselectedAsset: AppIcons.bottomNav.smartViewUnselected,
    ),
    AppNavItem(
      label: 'Inbox',
      selectedAsset: AppIcons.bottomNav.inboxSelected,
      unselectedAsset: AppIcons.bottomNav.inboxUnselected,
    ),
    AppNavItem(
      label: 'Agents',
      selectedAsset: AppIcons.bottomNav.aiSelected,
      unselectedAsset: AppIcons.bottomNav.aiUnselected,
    ),
    AppNavItem(
      label: 'Submits',
      selectedAsset: AppIcons.bottomNav.submissionsSelected,
      unselectedAsset: AppIcons.bottomNav.submissionsUnselected,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final media = MediaQuery.of(context);
    final navHeight = AppBottomNav.heightFor(context);
    return Obx(
      () => PopScope(
        canPop: !c.isTourActive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) c.cancelTour();
        },
        child: _scaffold(c, media, navHeight),
      ),
    );
  }

  Widget _scaffold(
    HomeShellController c,
    MediaQueryData media,
    double navHeight,
  ) {
    return Scaffold(
      backgroundColor: AppColors.white,
      resizeToAvoidBottomInset: false,
      body: Obx(() {
        if (c.isRetired.value) {
          return const AppStateView(
            state: AppViewState.loading,
            child: SizedBox.shrink(),
          );
        }
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  // The bar stays put under the keyboard, so a tab only gives up the
                  // part of the keyboard that rises above the bar.
                  child: MediaQuery(
                    data: media.copyWith(
                      viewInsets: media.viewInsets.copyWith(
                        bottom: math.max(
                          0,
                          media.viewInsets.bottom - navHeight,
                        ),
                      ),
                    ),
                    child: Obx(() {
                      final active = c.tab.value;
                      return Stack(
                        children: [
                          for (var i = 0; i < _screens.length; i++)
                            if (c.isBuilt[i])
                              _TabLayer(
                                key: ValueKey(HomeTab.values[i]),
                                animation: c.crossfade,
                                isActive: HomeTab.values[i] == active,
                                isLeaving: HomeTab.values[i] == c.previous,
                                child: _screens[i],
                              ),
                        ],
                      );
                    }),
                  ),
                ),
                Obx(
                  () => KeyedSubtree(
                    key: c.navKey,
                    child: AppBottomNav(
                      index: c.tab.value.index,
                      onSelected: (i) => c.select(HomeTab.values[i]),
                      items: navItems(hasUnread: c.hasUnread.value),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// One tab. Every visited tab stays built (its state is kept); only the
/// active one and the one fading out are shown. The new tab fades in while
/// rising by [AppDistances.tab].
class _TabLayer extends StatelessWidget {
  const _TabLayer({
    super.key,
    required this.animation,
    required this.isActive,
    required this.isLeaving,
    required this.child,
  });

  final Animation<double> animation;
  final bool isActive;
  final bool isLeaving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isReduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final t = AppCurves.out.transform(animation.value);
        final isFading = !isActive && isLeaving && t < 1;
        final isVisible = isActive || isFading;
        final opacity = isActive ? t : (1 - t);
        final rise = isActive && !isReduced ? (1 - t) * AppDistances.tab : 0.0;
        return Offstage(
          offstage: !isVisible,
          child: TickerMode(
            enabled: isVisible,
            child: IgnorePointer(
              ignoring: !isActive,
              child: Opacity(
                opacity: opacity.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, rise),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
