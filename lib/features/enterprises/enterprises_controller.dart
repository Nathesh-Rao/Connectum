import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_motion.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/models/identity_info.dart';
import '../../data/models/ids.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';

class EnterprisesController extends GetxController {
  EnterprisesController({
    required this.auth,
    required this.store,
    required this.session,
    required this.connectivity,
  });

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final AuthRepository auth;
  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;

  final isRefreshing = false.obs;
  final loadError = RxnString();
  final message = RxnString();
  final enteringId = RxnString();
  final isCopied = false.obs;
  Timer? _copiedTimer;
  final blockedReasons = <String>[].obs;

  // join
  final joinQuery = TextEditingController();
  final results = <EnterpriseHit>[].obs;
  final isJoinBusy = false.obs;
  final joinMessage = RxnString();
  final selected = Rxn<EnterpriseHit>();
  final categories = <String>[].obs;
  final joinOutcome = RxnString();
  Map<String, dynamic> _page = {};
  Timer? _debounce;

  IdentityInfo? get identity => store.identity.value;
  String? get currentOrgId =>
      store.orgId ?? (SeedUi.isActive ? SeedUi.currentOrgId : null);
  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  @override
  Future<void> refresh() async {
    if (isRefreshing.value || identity == null) return;
    loadError.value = null;
    if (isOffline) return;
    isRefreshing.value = true;
    try {
      await auth.refreshMe();
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') {
        _toLogin();
      } else {
        loadError.value = ApiMessages.of(e);
      }
    } finally {
      isRefreshing.value = false;
    }
  }

  void _toLogin() {
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
    if (!m.isActive) {
      message.value = m.status == 'pending'
          ? ApiMessages.of(const ApiException('pending_approval', ''))
          : ApiMessages.of(const ApiException('rejected', ''));
      return;
    }
    if (isOffline) {
      message.value = 'Connect to the internet to enter an enterprise.';
      return;
    }
    enteringId.value = m.enterprise;
    try {
      await auth.enter(m.enterprise);
      Get.offAllNamed(AppRoutes.chats);
    } on UnsupportedStep catch (e) {
      blockedReasons.assignAll(e.reasons);
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') {
        _toLogin();
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

  // ---- join by search --------------------------------------------------------------

  void resetJoin() {
    joinQuery.clear();
    results.clear();
    selected.value = null;
    categories.clear();
    joinMessage.value = null;
    joinOutcome.value = null;
  }

  /// "XXXX-XXXX" when the text reads as a Connectum ID (the web client's
  /// forgiving rules: case, spaces and dashes ignored, O/0 and I/L/1 alike).
  static String? asConnectumId(String text) {
    final chars = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .split('')
        .map(
          (c) => switch (c) {
            'O' => '0',
            'I' || 'L' => '1',
            'U' => 'V',
            _ => c,
          },
        )
        .join();
    if (chars.length != 8 ||
        chars.split('').any((c) => !_alphabet.contains(c))) {
      return null;
    }
    return '${chars.substring(0, 4)}-${chars.substring(4)}';
  }

  void onJoinQueryChanged(String text) {
    _debounce?.cancel();
    joinMessage.value = null;
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(text.trim()),
    );
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      results.clear();
      return;
    }
    isJoinBusy.value = true;
    try {
      final id = asConnectumId(query);
      if (id != null) {
        final hit = await auth.byId(id);
        results.assignAll(hit == null ? [] : [hit]);
      } else {
        results.assignAll(await auth.search(query));
      }
      if (results.isEmpty) joinMessage.value = 'No enterprise found.';
    } on ApiException catch (e) {
      joinMessage.value = ApiMessages.of(e);
    } finally {
      isJoinBusy.value = false;
    }
  }

  Future<void> selectEnterprise(EnterpriseHit hit) async {
    isJoinBusy.value = true;
    joinMessage.value = null;
    try {
      _page = await auth.publicPage(hit.id);
      selected.value = hit;
      categories.assignAll(((_page['categories'] as List?) ?? []).map(idText));
      if (categories.isEmpty) {
        joinMessage.value =
            "This enterprise isn't open for joining from the app yet.";
      }
    } on ApiException catch (e) {
      joinMessage.value = ApiMessages.of(e);
    } finally {
      isJoinBusy.value = false;
    }
  }

  Future<void> join(String category) async {
    final hit = selected.value;
    if (hit == null || isJoinBusy.value) return;
    final extra =
        (((_page['onboarding'] as Map?)?[category] as Map?)?['requiredFields']
            as List?) ??
        [];
    if (extra.isNotEmpty) {
      joinMessage.value =
          'Joining as $category needs more details than the mobile app supports yet.';
      return;
    }
    isJoinBusy.value = true;
    joinMessage.value = null;
    try {
      final check = await auth.joinCheck(hit.id, category);
      final fields = (check['fields'] as Map?) ?? {};
      if (fields.isNotEmpty) {
        joinMessage.value = '${fields.values.first}';
        return;
      }
      final data = await auth.join(hit.id, category);
      joinOutcome.value = data['status'] == 'pending'
          ? 'Request sent. You can enter ${hit.name} once an administrator approves it.'
          : 'You joined ${hit.name}.';
      await refresh();
    } on ApiException catch (e) {
      if (e.code == 'unauthenticated') {
        _toLogin();
      } else {
        joinMessage.value = ApiMessages.of(e);
      }
    } finally {
      isJoinBusy.value = false;
    }
  }

  @override
  void onClose() {
    _copiedTimer?.cancel();
    _debounce?.cancel();
    joinQuery.dispose();
    super.onClose();
  }
}
