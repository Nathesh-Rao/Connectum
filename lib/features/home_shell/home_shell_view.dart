import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../ai_agents/ai_agents_view.dart';
import '../chats/chats_view.dart';
import '../profile/profile_view.dart';
import '../submissions/submissions_view.dart';
import 'home_shell_controller.dart';

class HomeShellView extends GetView<HomeShellController> {
  const HomeShellView({super.key});

  static const _screens = <Widget>[
    ChatsView(),
    AiAgentsView(),
    SubmissionsView(),
    ProfileView(),
  ];

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final media = MediaQuery.of(context);
    final navHeight = AppBottomNav.heightFor(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Expanded(
            // The bar stays put under the keyboard, so a tab only gives up the
            // part of the keyboard that rises above the bar.
            child: MediaQuery(
              data: media.copyWith(
                viewInsets: media.viewInsets.copyWith(
                  bottom: math.max(0, media.viewInsets.bottom - navHeight),
                ),
              ),
              child: Obx(() {
                final active = c.index.value;
                return Stack(
                  children: [
                    for (var i = 0; i < _screens.length; i++)
                      if (c.isBuilt[i])
                        _TabLayer(
                          animation: c.crossfade,
                          isActive: i == active,
                          isLeaving: i == c.previous,
                          child: _screens[i],
                        ),
                  ],
                );
              }),
            ),
          ),
          Obx(
            () => AppBottomNav(
              index: c.index.value,
              onSelected: c.select,
              items: [
                AppNavItem(
                  label: 'Chats',
                  icon: Icons.chat_bubble_outline,
                  showDot: c.hasUnread.value,
                ),
                const AppNavItem(
                  label: 'AI Agents',
                  icon: Icons.auto_awesome_outlined,
                ),
                const AppNavItem(
                  label: 'Submissions',
                  icon: Icons.description_outlined,
                ),
                const AppNavItem(label: 'Profile', icon: Icons.person_outline),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tab. Every visited tab stays built (its state is kept); only the
/// active one and the one fading out are shown. The new tab fades in while
/// rising by [AppDistances.tab].
class _TabLayer extends StatelessWidget {
  const _TabLayer({
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
