import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/home_reload.dart';
import '../../core/theme/app_motion.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/models/identity_info.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../connect/connect_controller.dart';

class EnterprisesController extends GetxController with WidgetsBindingObserver {
  EnterprisesController({
    required this.auth,
    required this.store,
    required this.session,
    required this.connectivity,
    required this.connect,
  });

  final AuthRepository auth;
  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;
  final ConnectController connect;

  final isRefreshing = false.obs;
  final loadError = RxnString();
  final message = RxnString();
  final enteringId = RxnString();
  final isCopied = false.obs;
  Timer? _copiedTimer;
  final blockedReasons = <String>[].obs;

  IdentityInfo? get identity => store.identity.value;
  String? get currentOrgId =>
      store.orgId ?? (SeedUi.isActive ? SeedUi.currentOrgId : null);
  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  Future<void> refresh() async {
    if (isRefreshing.value || identity == null || SeedUi.isActive) return;
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
          message.value = '${m.name} approved your request. You can enter now.';
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

  Future<void> enter(EnterpriseMembership m) async {
    if (enteringId.value != null) return;
    message.value = null;
    if (SeedUi.isActive && !m.isActive) {
      message.value = ApiMessages.of(
        ApiException(
          m.status == 'pending' ? 'pending_approval' : 'rejected',
          '',
        ),
      );
      return;
    }
    if (isOffline) {
      message.value = 'Connect to the internet to enter an enterprise.';
      return;
    }
    enteringId.value = m.enterprise;
    try {
      await auth.enter(m.enterprise);
      await HomeReload.run();
    } on UnsupportedStep catch (e) {
      blockedReasons.assignAll(e.reasons);
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') {
        toLogin();
      } else {
        message.value = ApiMessages.of(e);
      }
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
    super.onClose();
  }
}
