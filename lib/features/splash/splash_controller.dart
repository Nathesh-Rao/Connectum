import 'dart:async';

import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/theme/app_motion.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';

class SplashController extends GetxController {
  SplashController({
    required this.session,
    required this.store,
    required this.deepLinks,
  });

  static const onboardingSeenKey = 'onboarding.seen';

  final SessionRepository session;
  final SessionStore store;
  final DeepLinkService deepLinks;

  @override
  void onReady() {
    super.onReady();
    _route();
  }

  Future<void> _route() async {
    final started = DateTime.now();
    // Neither step may hang the splash.
    await session.ready.timeout(const Duration(seconds: 4), onTimeout: () {});
    final seen = await store
        .readValue(onboardingSeenKey)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    final route = store.hasEnterpriseSession
        ? AppRoutes.chats
        : store.hasIdentity
        ? AppRoutes.enterprises
        : seen == 'true'
        ? AppRoutes.authentication
        : AppRoutes.onboarding;
    final remaining =
        AppDurations.splashHold - DateTime.now().difference(started);
    if (!remaining.isNegative) await Future<void>.delayed(remaining);
    Get.offNamed(route);
    if (route != AppRoutes.authentication && route != AppRoutes.onboarding) {
      deepLinks.openPending();
    }
  }
}
