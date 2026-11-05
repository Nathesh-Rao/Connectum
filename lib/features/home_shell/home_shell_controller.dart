import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/routes/home_reload.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/e2e/e2e_texts.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/notifications/local_notification_service.dart';
import '../notifications/notification_router.dart';
import '../notifications/widgets/notification_permission_sheet.dart';
import '../security/security_controller.dart';
import '../security/widgets/security_sheets.dart';

class HomeShellController extends GetxController
    with GetSingleTickerProviderStateMixin {
  HomeShellController({
    required this.conversations,
    required this.security,
    required this.links,
    required this.notifications,
    required this.notificationRouter,
  });

  static const tabRoutes = [
    AppRoutes.chats,
    AppRoutes.aiAgents,
    AppRoutes.submissions,
    AppRoutes.profile,
  ];

  final ConversationRepository conversations;
  final SecurityController security;
  final DeepLinkService links;
  final LocalNotificationService notifications;
  final NotificationRouter notificationRouter;

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
    notificationRouter.selectTab = select;
    HomeReload.retireHome = () => isRetired.value = true;
    HomeReload.restoreHome = () => isRetired.value = false;
    final start = tabRoutes.indexOf(Get.currentRoute);
    if (start > 0) {
      index.value = start;
      previous = start;
      isBuilt[start] = true;
    }
    ever(conversations.conversations, (_) => _updateDot());
    ever(SeedUi.chatsState, (_) => _updateDot());
    ever(security.e2e.phase, _onSetupPhase);
    ever(security.e2e.notice, (_) => _syncNotice());
    ever(security.e2e.lateHint, (_) => _syncNotice());
    ever(security.e2e.isLate, (_) => _syncNotice());
    _notices = security.e2e.notices.listen(_onE2eNotice);
    _syncNotice();
    _updateDot();
  }

  StreamSubscription<E2eNotice>? _notices;

  void _onE2eNotice(E2eNotice n) => AppNotices.show(
    n.isNewDevice
        ? E2eTexts.newDeviceTemplate(hasLabels: n.labels.isNotEmpty)
        : E2eTexts.keyChangedTemplate,
    values: {
      'user': '@${n.user}',
      if (n.labels.isNotEmpty) 'devices': n.labels.join(', '),
    },
    variant: AppNoticeVariant.warning,
    key: 'notice-e2e-${n.isNewDevice ? 'device' : 'key'}-${n.user}',
  );

  @override
  void onReady() {
    super.onReady();
    links.resume();
    notificationRouter.markHomeReady();
    unawaited(_explainNotifications());
  }

  /// Once, after sign-in, on the first Home: a short explainer, then the
  /// system prompt only if the person agrees.
  Future<void> _explainNotifications() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    final context = Get.context;
    if (isClosed || context == null || !context.mounted) return;
    if (!notifications.shouldExplain) return;
    final isAllowed = await NotificationPermissionSheet.show(context);
    if (isAllowed == true) {
      await notifications.request();
    } else {
      await notifications.markAsked();
    }
  }

  static const _lateKey = 'notice-late';
  static const _noticeKey = 'notice-secure';

  void _syncNotice() {
    final e2e = security.e2e;
    if (e2e.isLate.value && e2e.lateHint.value.isNotEmpty) {
      AppNotices.hide(_noticeKey);
      AppNotices.show(
        'This phone is still catching up.',
        key: _lateKey,
        title: "Earlier messages aren't shown yet",
        icon: Icons.lock_outline,
        actionLabel: 'See Security',
        onAction: openSecurity,
        isPersistent: true,
        onDismiss: security.dismissLateHint,
      );
      return;
    }
    AppNotices.hide(_lateKey);
    final text = e2e.notice.value;
    if (text.isEmpty) {
      AppNotices.hide(_noticeKey);
      return;
    }
    final isReadable = text == E2eRepository.readableText;
    AppNotices.show(
      isReadable
          ? 'They are now shown on this phone.'
          : "Messages from before this phone joined can't be read here.",
      key: _noticeKey,
      title: isReadable
          ? 'Earlier messages are readable'
          : 'Secure messaging is on',
      icon: Icons.lock_outline,
      actionLabel: isReadable ? null : 'See Security',
      onAction: isReadable ? null : openSecurity,
      onDismiss: security.dismissNotice,
    );
  }

  void openSecurity() => Get.toNamed(AppRoutes.security);

  /// Opens the setup sheet when secure-messaging setup needs the person.
  /// A phone the person removed themselves is not nagged: Security offers it.
  /// The device-limit sheet opens once per organisation (see
  /// [SecurityController.limitGate]); after that the conversation and the
  /// composer carry a quiet banner instead.
  void _onSetupPhase(E2eSetupPhase phase) {
    final context = Get.context;
    if (context == null) return;
    if (phase == E2eSetupPhase.limit) {
      unawaited(SecuritySheets.openLimit(context, security));
    } else if (phase == E2eSetupPhase.removed ||
        phase == E2eSetupPhase.refused) {
      unawaited(SecuritySheets.openIssue(context, security));
    }
  }

  /// "See devices" on the banner: the person asked, so it opens again.
  void openDeviceLimit() {
    final context = Get.context;
    if (context == null) return;
    unawaited(SecuritySheets.openLimit(context, security, isRequested: true));
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
    notificationRouter.markHomeGone();
    _notices?.cancel();
    AppNotices.hide(_lateKey);
    AppNotices.hide(_noticeKey);
    crossfade.dispose();
    super.onClose();
  }
}
