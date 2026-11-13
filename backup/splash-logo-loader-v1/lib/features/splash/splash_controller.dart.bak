import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/routes/deep_link_service.dart';
import '../../core/widgets/logo_loader/logo_loader.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/session_store.dart';

class SplashController extends GetxController with WidgetsBindingObserver {
  SplashController({
    required this.session,
    required this.store,
    required this.deepLinks,
    this.resolveRoute,
    this.navigate,
    this.shouldReduceMotion,
  });

  // TUNE ME: splash timing
  static const startDelay = Duration(milliseconds: 400);
  static const extraRun = Duration(milliseconds: 2000);
  static const endDelay = Duration(milliseconds: 300);
  static const reducedMotionDelay = Duration(milliseconds: 300);

  static const onboardingSeenKey = 'onboarding.seen';

  final SessionRepository session;
  final SessionStore store;
  final DeepLinkService deepLinks;

  /// Test hooks: the splash work, the navigation and the reduced-motion check.
  final Future<String> Function()? resolveRoute;
  final void Function(String route)? navigate;
  final bool Function()? shouldReduceMotion;

  final loader = LogoLoaderController();

  final _timers = <Timer>{};
  bool _isStarted = false;
  bool _isClosed = false;
  bool _isNavigated = false;
  String? _pendingRoute;
  bool _isPaused = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onReady() {
    super.onReady();
    run();
  }

  @override
  void onClose() {
    _isClosed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    loader.dispose();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isPaused = state != AppLifecycleState.resumed;
    final route = _pendingRoute;
    if (!_isPaused && route != null && !_isClosed) {
      _pendingRoute = null;
      _go(route);
    }
  }

  /// The whole splash sequence. Runs once per controller.
  Future<void> run() async {
    if (_isStarted || _isClosed) return;
    _isStarted = true;
    final reduce =
        shouldReduceMotion?.call() ??
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    final work = _work();
    if (reduce) {
      final hold = _delay(reducedMotionDelay);
      final route = await work;
      await hold;
      _finish(route);
      return;
    }
    final isAnimating = _delay(startDelay).then((_) {
      if (!_isClosed) loader.start();
    });
    final route = await work;
    await isAnimating;
    await _delay(extraRun);
    if (_isClosed) return;
    await loader.stopAndWait();
    await _delay(endDelay);
    _finish(route);
  }

  Future<String> _work() async {
    try {
      return await (resolveRoute ?? _resolveRoute)();
    } catch (_) {
      return _fallbackRoute();
    }
  }

  Future<String> _resolveRoute() async {
    // Neither step may hang the splash.
    await session.ready.timeout(const Duration(seconds: 4), onTimeout: () {});
    final seen = await store
        .readValue(onboardingSeenKey)
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    await deepLinks.runFirstStart().timeout(
      const Duration(seconds: 6),
      onTimeout: () {},
    );
    return store.hasEnterpriseSession
        ? AppRoutes.chats
        : store.hasIdentity
        ? AppRoutes.enterprises
        : seen == 'true'
        ? AppRoutes.authentication
        : AppRoutes.onboarding;
  }

  String _fallbackRoute() {
    try {
      return store.hasEnterpriseSession
          ? AppRoutes.chats
          : store.hasIdentity
          ? AppRoutes.enterprises
          : AppRoutes.onboarding;
    } catch (_) {
      return AppRoutes.onboarding;
    }
  }

  Future<void> _delay(Duration d) {
    final done = Completer<void>();
    late final Timer timer;
    timer = Timer(d, () {
      _timers.remove(timer);
      done.complete();
    });
    _timers.add(timer);
    return done.future;
  }

  void _finish(String route) {
    if (_isClosed) return;
    if (_isPaused) {
      _pendingRoute = route;
      return;
    }
    _go(route);
  }

  void _go(String route) {
    if (_isNavigated || _isClosed) return;
    _isNavigated = true;
    if (navigate != null) {
      navigate!(route);
      return;
    }
    Get.offNamed(route);
    if (route != AppRoutes.authentication && route != AppRoutes.onboarding) {
      deepLinks.resume();
    }
  }
}
