import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/material.dart' show GlobalKey, Icons;
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/routes/home_reload.dart';
import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/features/notifications/notifications.dart';
import 'package:connectum/features/security/security.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/e2e/e2e_texts.dart';
import '../../data/notifications/local_notification_service.dart';
import '../../core/crash/crash_breadcrumbs.dart';
import '../../core/crash/crash_service.dart';
import 'home_tab.dart';

class HomeShellController extends GetxController
    with GetSingleTickerProviderStateMixin {
  HomeShellController({
    required this.conversations,
    required this.security,
    required this.links,
    required this.notifications,
    required this.notificationRouter,
    required this.smartView,
    this.tour,
  });

  static final tabRoutes = [for (final t in HomeTab.values) t.route];

  final ConversationRepository conversations;
  final SecurityController security;
  final DeepLinkService links;
  final LocalNotificationService notifications;
  final NotificationRouter notificationRouter;
  final SmartViewController smartView;
  final TourService? tour;

  /// The bottom bar, for the tours to point at.
  final navKey = GlobalKey(debugLabel: 'home-nav');

  bool get isTourActive => tour?.isActive.value ?? false;

  /// Back while a tour shows ends the tour and stays on the screen.
  void cancelTour() => tour?.cancel();

  final tab = HomeTab.chats.obs;
  final hasUnread = false.obs;

  /// Set by [openInbox] with `approvals: true`; the Inbox takes it (and
  /// clears it) when it opens the Approvals pane. Kept here so a request made
  /// before the Inbox exists, as on a cold start, is not lost.
  final approvalsRequest = false.obs;

  /// Set by [openInbox] with `recordId`: the Inbox shows that one record
  /// (a notification's "View submission") and takes the request.
  final recordRequest = Rxn<int>();

  /// Set by [openInbox] with `isList`: the Inbox shows its Records tab, the
  /// usual list (a "New submission" notification with no record number).
  final listRequest = false.obs;

  /// A form (its name) My Submissions should show only; set by `#tstruct`,
  /// read and cleared by the Submissions screen.
  final submissionsForm = RxnString();

  /// True once a reload is replacing this home: the content is unmounted
  /// before the controllers behind it are closed.
  final isRetired = false.obs;
  final isBuilt = <bool>[true, false, false, false, false];
  HomeTab previous = HomeTab.chats;
  late final AnimationController crossfade = AnimationController(
    vsync: this,
    duration: AppDurations.base,
    value: 1,
  );

  @override
  void onInit() {
    super.onInit();
    tour?.bottomBarKey = navKey;
    notificationRouter.selectTab = select;
    notificationRouter.openApprovals = () => openInbox(approvals: true);
    notificationRouter.openRecord = (id) => openInbox(recordId: id);
    notificationRouter.openInboxList = () => openInbox(isList: true);
    HomeReload.retireHome = () => isRetired.value = true;
    HomeReload.restoreHome = () => isRetired.value = false;
    final start = HomeTab.ofRoute(Get.currentRoute);
    if (start != null && start != HomeTab.chats) {
      tab.value = start;
      previous = start;
      isBuilt[start.index] = true;
      if (start == HomeTab.smartView) {
        fireAndLog(
          'home_shell_controller',
          () => smartView.enter(const SmartViewEntry.tab()),
        );
      }
    }
    ever(conversations.conversations, (_) => _updateDot());
    ever(SeedUi.chatsState, (_) => _updateDot());
    ever(security.e2e.phase, _onSetupPhase);
    ever(security.e2e.notice, (_) => _syncNotice());
    ever(security.e2e.lateHint, (_) => _syncNotice());
    ever(security.e2e.isLate, (_) => _syncNotice());
    _notices = security.e2e.notices.listen(
      _onE2eNotice,
      onError: streamOnError('home_shell_controller'),
    );
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
    fireAndLog('home_shell_controller', () => _explainNotifications());
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
      fireAndLog(
        'home_shell_controller',
        () => SecuritySheets.openLimit(context, security),
      );
    } else if (phase == E2eSetupPhase.removed ||
        phase == E2eSetupPhase.refused) {
      fireAndLog(
        'home_shell_controller',
        () => SecuritySheets.openIssue(context, security),
      );
    }
  }

  /// "See devices" on the banner: the person asked, so it opens again.
  void openDeviceLimit() {
    final context = Get.context;
    if (context == null) return;
    fireAndLog(
      'home_shell_controller',
      () => SecuritySheets.openLimit(context, security, isRequested: true),
    );
  }

  void _updateDot() {
    final source = SeedUi.isActive
        ? SeedUi.conversations()
        : conversations.conversations;
    hasUnread.value = source.any(
      (c) => c.unread > 0 && !c.isMuted && !c.isArchived,
    );
  }

  /// `#tstruct <name>`: leaves the open chat and shows My Submissions of that
  /// form.
  void openSubmissionsOf(String formName) {
    submissionsForm.value = formName;
    Get.until((r) => tabRoutes.contains(r.settings.name));
    select(HomeTab.submits);
  }

  /// `#view`, `#view <name>`: leaves the open chat, shows the Smart view tab
  /// and tells it how it was entered. Nothing is stacked: a second call on the
  /// tab only updates it.
  void openSmartView(SmartViewEntry entry) {
    Get.until((r) => tabRoutes.contains(r.settings.name));
    select(HomeTab.smartView, entry: entry);
  }

  /// `#inbox`: leaves the open chat and shows the Inbox tab. The Smart view
  /// tab keeps its own state while the Inbox is shown. With [approvals] the
  /// Approvals pane is open on it (notifications, the Work Space icon).
  void openInbox({bool approvals = false, int? recordId, bool isList = false}) {
    if (approvals) approvalsRequest.value = true;
    if (isList) listRequest.value = true;
    if (recordId != null) recordRequest.value = recordId;
    Get.until((r) => tabRoutes.contains(r.settings.name));
    select(HomeTab.inbox);
  }

  void select(HomeTab next, {SmartViewEntry? entry}) {
    final isSmart = next == HomeTab.smartView;
    final isMoving = next != tab.value;
    if (isMoving) {
      previous = tab.value;
      CrashBreadcrumbs.add(Crumb.tab, code: next.name);
      CrashService.key('tab', next.name);
      isBuilt[next.index] = true;
      tab.value = next;
      crossfade.forward(from: 0);
      smartView.setActive(isSmart);
    }
    if (isSmart && (isMoving || entry != null)) {
      fireAndLog(
        'home_shell_controller',
        () => smartView.enter(entry ?? const SmartViewEntry.tab()),
      );
    }
  }

  @override
  void onClose() {
    if (tour?.bottomBarKey == navKey) tour?.bottomBarKey = null;
    notificationRouter.markHomeGone();
    _notices?.cancel();
    AppNotices.hide(_lateKey);
    AppNotices.hide(_noticeKey);
    crossfade.dispose();
    super.onClose();
  }
}
