import 'dart:async';

import '../../demo/demo_mode.dart';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/home_reload.dart';
import '../../core/theme/app_motion.dart';
import '../../core/utils/app_settings.dart';
import '../../data/repositories/qr_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../chats/enterprise_switcher_controller.dart';
import '../qr/qr_sheet.dart';

class ProfileController extends GetxController {
  ProfileController({
    required this.store,
    required this.session,
    required this.connectivity,
    required this.switcher,
    required this.qr,
  });

  final SessionStore store;
  final SessionRepository session;
  final ConnectivityService connectivity;
  final EnterpriseSwitcherController switcher;
  final QrRepository qr;

  final isCopied = false.obs;
  final isLoggingOut = false.obs;
  final version = RxnString();
  Timer? _copiedTimer;

  @override
  void onInit() {
    super.onInit();
    AppSettings.version().then((v) => version.value = v);
  }

  String get name {
    if (SeedUi.isActive) return SeedUi.profile().name;
    final identity = store.identity.value;
    if (identity != null && identity.name.isNotEmpty) return identity.name;
    return store.userId ?? identity?.username ?? '';
  }

  String get username => SeedUi.isActive
      ? SeedUi.profile().username
      : (store.identity.value?.username ?? '');

  String get email => SeedUi.isActive
      ? SeedUi.profile().email
      : (store.identity.value?.email ?? '');

  String get connectumId => SeedUi.isActive
      ? SeedUi.profile().connectumId
      : (store.identity.value?.connectumId ?? '');

  String get organisation => switcher.currentName;

  String get category {
    if (SeedUi.isActive) return SeedUi.profile().category;
    for (final m in switcher.enterprises) {
      if (m.enterprise == switcher.currentOrgId) return m.category;
    }
    return '';
  }

  bool get isOnline =>
      connectivity.state.value == AppConnectivity.online || SeedUi.isActive;

  Future<void> copyConnectumId() async {
    if (connectumId.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: connectumId));
    isCopied.value = true;
    _copiedTimer?.cancel();
    _copiedTimer = Timer(AppDurations.copiedHold, () => isCopied.value = false);
  }

  void prepareSwitcher() => switcher.prepare();

  Future<void> openQr(BuildContext context) =>
      QrSheet.show(context, repository: qr);

  void openSecurity() => Get.toNamed(AppRoutes.security);

  void replayIntroduction() =>
      Get.toNamed(AppRoutes.onboarding, arguments: {'replay': true});

  Future<int> unsentCount() async =>
      SeedUi.isActive ? SeedUi.profileUnsent.value : session.unsentCount();

  /// Takes the home down first (as an enterprise switch does), then signs out
  /// everywhere and opens the sign-in screen. A failed server call never
  /// blocks the local sign-out.
  Future<void> logOut() async {
    if (isLoggingOut.value) return;
    isLoggingOut.value = true;
    try {
      if (SeedUi.isActive && !DemoMode.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        Get.back<void>();
        return;
      }
      final retire = HomeReload.retireHome;
      HomeReload.retireHome = null;
      retire?.call();
      await WidgetsBinding.instance.endOfFrame;
      await session.logOut(notice: "You're logged out.");
    } finally {
      isLoggingOut.value = false;
    }
  }

  @override
  void onClose() {
    _copiedTimer?.cancel();
    super.onClose();
  }
}
