import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/routes/home_reload.dart';
import '../../core/widgets/app_highlight_text.dart';
import '../../core/utils/connect_code.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/theme/app_motion.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/models/identity_info.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../connect/connect_controller.dart';
import '../connect/connect_view.dart';

enum InviteStep { none, checking, entering, waiting, rejected, failed }

class EnterprisesController extends GetxController with WidgetsBindingObserver {
  EnterprisesController({
    required this.auth,
    required this.store,
    required this.session,
    required this.connectivity,
    required this.connect,
    required this.links,
  });

  final AuthRepository auth;
  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;
  final ConnectController connect;
  final DeepLinkService links;

  final isRefreshing = false.obs;
  final loadError = RxnString();
  final message = RxnString();
  final enteringId = RxnString();
  final isCopied = false.obs;
  Timer? _copiedTimer;
  final blockedReasons = <String>[].obs;

  // The pending invite link carried on after sign-in: join, wait, enter.
  final inviteStep = InviteStep.none.obs;
  final inviteOrg = RxnString();
  final inviteNote = RxnString();

  /// Names in [inviteNote] and in the next [message] (`{key}` placeholders).
  Map<String, String> inviteValues = const {};
  Map<String, String> messageValues = const {};
  Future<void>? _inFlight;
  String? _lastMessage;
  String? _offeredLink;
  bool _isJoinSheetOpen = false;
  EnterpriseMembership? _retryEntry;

  IdentityInfo? get identity => store.identity.value;
  String? get currentOrgId =>
      store.orgId ?? (SeedUi.isActive ? SeedUi.currentOrgId : null);
  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    ever(message, (text) {
      if (text == null) {
        AppNotices.hide(_lastMessage ?? '');
        return;
      }
      final values = messageValues;
      messageValues = const {};
      _lastMessage = AppHighlightText.plain(text, values);
      AppNotices.show(
        text,
        values: values,
        onDismiss: () => message.value = null,
      );
    });
    ever(links.joinRequest, (_) => _openRequestedJoin());
    ever(links.pending, (target) {
      if (target != null) continueInvite();
    });
  }

  @override
  void onReady() {
    super.onReady();
    if (links.pending.value == null) {
      refresh();
    } else {
      continueInvite();
    }
    _openRequestedJoin();
  }

  void _openRequestedJoin() {
    final link = links.joinRequest.value;
    if (link == null) return;
    links.joinRequest.value = null;
    openJoinSheet(link: link);
  }

  /// The "Join another enterprise" sheet; with [link] it opens on that
  /// enterprise instead of the scanner.
  void openJoinSheet({ConnectCode? link}) {
    final context = Get.context;
    if (context == null) return;
    connect.open(link: link);
    _isJoinSheetOpen = true;
    AppBottomSheet.show<void>(
      context,
      title: 'Join another enterprise',
      child: ConnectView(onEnter: enter),
    ).whenComplete(() {
      connect.close();
      _isJoinSheetOpen = false;
      unawaited(refresh());
      continueInvite(isAfterJoin: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (inviteStep.value == InviteStep.waiting) {
      continueInvite();
    } else {
      refresh();
    }
  }

  static String _plain(String id) => id.replaceAll('-', '').toUpperCase();

  EnterpriseMembership? _memberOf(ConnectCode target) {
    final org = _plain(target.org ?? target.code);
    for (final m in identity?.enterprises ?? const <EnterpriseMembership>[]) {
      if (_plain(m.enterprise) == org) return m;
    }
    return null;
  }

  /// Carries the pending link on once the person has an account: enters the
  /// organisation it names when they are a member, waits when the request is
  /// not approved yet, and offers to join when they are not a member. A
  /// person's link then reaches the Stage 1 confirm sheet from inside.
  ///
  /// Inside another organisation only a person's link carries on, and only
  /// right after the join sheet: it enters the organisation the person has
  /// just joined. Waiting for approval is then picked up by
  /// [DeepLinkService.resume], and the person step runs in the new home.
  Future<void> continueInvite({bool isAfterJoin = false}) async {
    final target = links.pending.value;
    if (target == null) {
      inviteStep.value = InviteStep.none;
      return;
    }
    final isInSession = store.hasEnterpriseSession;
    if (isInSession && !(target.isPersonLink && isAfterJoin)) return;
    if (identity == null ||
        _isJoinSheetOpen ||
        inviteStep.value == InviteStep.checking ||
        inviteStep.value == InviteStep.entering) {
      return;
    }
    inviteStep.value = InviteStep.checking;
    inviteNote.value = null;
    if (isOffline && !SeedUi.isActive) {
      _failInvite('Connect to the internet to continue.');
      return;
    }
    await refresh();
    final loadFailure = loadError.value;
    if (loadFailure != null) {
      _failInvite(loadFailure);
      return;
    }
    if (links.pending.value?.linkText != target.linkText) {
      inviteStep.value = InviteStep.none;
      return;
    }
    final m = _memberOf(target);
    if (isInSession && (m == null || !m.isActive)) {
      inviteStep.value = InviteStep.none;
      return;
    }
    if (m == null) {
      inviteStep.value = InviteStep.none;
      if (_offeredLink != target.linkText) {
        _offeredLink = target.linkText;
        openJoinSheet(link: target);
      }
      return;
    }
    inviteOrg.value = m.name;
    if (m.isActive) {
      inviteStep.value = InviteStep.entering;
      await enter(m);
      final failure = message.value;
      if (failure != null || blockedReasons.isNotEmpty) {
        message.value = null;
        _failInvite(failure ?? 'This account needs a step the app cannot do.');
      }
    } else if (m.status == 'pending') {
      inviteStep.value = InviteStep.waiting;
    } else {
      inviteStep.value = InviteStep.rejected;
      await links.clear(only: target);
    }
  }

  void _failInvite(String note, {Map<String, String> values = const {}}) {
    inviteValues = values;
    inviteNote.value = note;
    inviteStep.value = InviteStep.failed;
  }

  void dismissInvite() {
    inviteStep.value = InviteStep.none;
    inviteNote.value = null;
    unawaited(links.clear());
  }

  @override
  Future<void> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<void> _refresh() async {
    if (identity == null || SeedUi.isActive) return;
    loadError.value = null;
    if (isOffline) return;
    isRefreshing.value = true;
    final before = {
      for (final m in identity!.enterprises) m.enterprise: m.status,
    };
    try {
      final next = await auth.refreshMe();
      for (final m in next?.enterprises ?? const <EnterpriseMembership>[]) {
        if (before[m.enterprise] == 'pending' && m.isActive) {
          messageValues = {'name': m.name, 'you': 'You'};
          message.value = '{name} approved your request. {you} can enter now.';
        }
      }
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') {
        toLogin();
      } else {
        loadError.value = ApiMessages.of(e);
      }
    } finally {
      isRefreshing.value = false;
    }
  }

  void toLogin() {
    session.loginNotice.value = SessionRepository.endedNotice;
    Get.offAllNamed(AppRoutes.authentication);
  }

  Future<void> copyConnectumId() async {
    final id = identity?.connectumId ?? '';
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    isCopied.value = true;
    _copiedTimer?.cancel();
    _copiedTimer = Timer(AppDurations.copiedHold, () => isCopied.value = false);
  }

  void retryInvite() {
    final entry = _retryEntry;
    if (entry != null) {
      unawaited(enter(entry));
    } else {
      unawaited(continueInvite());
    }
  }

  /// The tapped tile's status is re-read from the server first, so a request
  /// approved in the meantime counts as active.
  Future<void> enter(EnterpriseMembership tapped) async {
    if (enteringId.value != null) return;
    message.value = null;
    _retryEntry = null;
    if (inviteStep.value == InviteStep.failed) {
      inviteStep.value = InviteStep.none;
      inviteNote.value = null;
    }
    if (SeedUi.isActive && !tapped.isActive) {
      message.value = ApiMessages.of(
        ApiException(
          tapped.status == 'pending' ? 'pending_approval' : 'rejected',
          '',
        ),
      );
      return;
    }
    if (tapped.enterprise == currentOrgId &&
        store.hasEnterpriseSession &&
        HomeReload.observer.routes.isNotEmpty) {
      Get.until((route) => HomeReload.observer.routes.contains(route));
      return;
    }
    if (isOffline) {
      message.value = 'Connect to the internet to enter an enterprise.';
      return;
    }
    enteringId.value = tapped.enterprise;
    try {
      await refresh();
      message.value = null;
      var m = tapped;
      if (loadError.value == null) {
        for (final fresh in identity?.enterprises ?? const []) {
          if (fresh.enterprise == tapped.enterprise) m = fresh;
        }
        if (!m.isActive) {
          message.value = ApiMessages.of(
            ApiException(
              m.status == 'pending' ? 'pending_approval' : 'rejected',
              '',
            ),
          );
          return;
        }
      }
      await auth.enter(m.enterprise);
      final target = links.pending.value;
      if (target != null &&
          !target.isPersonLink &&
          _plain(target.code) == _plain(m.enterprise)) {
        await links.clear(only: target);
      }
      await HomeReload.run();
    } on UnsupportedStep catch (e) {
      blockedReasons.assignAll(e.reasons);
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') {
        toLogin();
      } else {
        message.value = ApiMessages.of(e);
      }
    } catch (e, stack) {
      debugPrint('enter ${tapped.enterprise} failed: $e\n$stack');
      _retryEntry = tapped;
      _failInvite(
        "Couldn't open {name}. Check your connection and try again.",
        values: {'name': tapped.name},
      );
    } finally {
      enteringId.value = null;
    }
  }

  Future<void> signOut() async {
    await auth.signOutIdentity();
    Get.offAllNamed(AppRoutes.authentication);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _copiedTimer?.cancel();
    AppNotices.hide(_lastMessage ?? '');
    super.onClose();
  }
}
