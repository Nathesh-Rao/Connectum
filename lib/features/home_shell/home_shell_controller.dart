import 'package:flutter/animation.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/home_reload.dart';
import '../../core/theme/app_motion.dart';
import '../../data/repositories/conversation_repository.dart';

class HomeShellController extends GetxController
    with GetSingleTickerProviderStateMixin {
  HomeShellController({required this.conversations});

  static const tabRoutes = [
    AppRoutes.chats,
    AppRoutes.aiAgents,
    AppRoutes.submissions,
    AppRoutes.profile,
  ];

  final ConversationRepository conversations;

  final index = 0.obs;
  final hasUnread = false.obs;

  /// True once a reload is replacing this home: the content is unmounted
  /// before the controllers behind it are closed.
  final isRetired = false.obs;
  final isBuilt = <bool>[true, false, false, false];
  int previous = 0;
  late final AnimationController crossfade = AnimationController(
    vsync: this,
    duration: AppDurations.base,
    value: 1,
  );

  @override
  void onInit() {
    super.onInit();
    HomeReload.retireHome = () => isRetired.value = true;
    final start = tabRoutes.indexOf(Get.currentRoute);
    if (start > 0) {
      index.value = start;
      previous = start;
      isBuilt[start] = true;
    }
    ever(conversations.conversations, (_) => _updateDot());
    ever(SeedUi.chatsState, (_) => _updateDot());
    _updateDot();
  }

  void _updateDot() {
    final source = SeedUi.isActive
        ? SeedUi.conversations()
        : conversations.conversations;
    hasUnread.value = source.any(
      (c) => c.unread > 0 && !c.isMuted && !c.isArchived,
    );
  }

  void select(int next) {
    if (next == index.value) return;
    previous = index.value;
    isBuilt[next] = true;
    index.value = next;
    crossfade.forward(from: 0);
  }

  @override
  void onClose() {
    crossfade.dispose();
    super.onClose();
  }
}
