import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
// ignore: implementation_imports
import 'package:get/get_navigation/src/router_report.dart';

import '../debug/connect_flow_log.dart';
import 'app_routes.dart';

/// Reloads the home area (after an enterprise switch) without the new home
/// sharing controllers with the old one.
///
/// GetX deletes a route's controllers by type when the route is disposed. A
/// new Chats route pushed over the old one registers the same types, so the
/// old route's disposal (after the transition) used to delete the controllers
/// the new screen was already using. The old home is therefore taken down
/// first: its content is unmounted, then its controllers are closed, and only
/// then the new route registers its own.
class HomeReload {
  HomeReload._();

  /// Knows every home route in the stack, so a reload frees all of them
  /// however the enterprises screen was reached.
  static final observer = _HomeObserver();

  /// Set by the home shell controller that is alive: unmounts its content.
  static VoidCallback? retireHome;

  /// Undoes [retireHome] when a reload fails, so the home is never left empty.
  static VoidCallback? restoreHome;

  /// The home route, noted by a screen that opens another screen over it
  /// (the enterprise switcher's "Join another enterprise"), so a reload that
  /// starts from there still takes the home down first.
  static Route<dynamic>? homeBelow;

  /// Open conversation screens: each can be unmounted and closed on its own,
  /// so a reload takes them down before the new home registers.
  static final overlays =
      <String, ({VoidCallback retire, VoidCallback close})>{};

  static int _running = 0;

  /// True from the start of a reload until one frame after the new home is
  /// pushed. A sheet that closes meanwhile was taken down by the reload.
  static bool get isRunning => _running > 0;

  /// Completes when no reload is running and none started in the frame after
  /// the last one finished: the new home is built and stable.
  static Future<void> settled() async {
    do {
      while (isRunning) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await WidgetsBinding.instance.endOfFrame;
    } while (isRunning);
  }

  static Future<void> run() async {
    final restore = restoreHome;
    _running++;
    ConnectFlowLog.log('homereload start', {'running': _running});
    try {
      await _run();
    } catch (_) {
      restore?.call();
      rethrow;
    } finally {
      _running--;
      ConnectFlowLog.log('homereload end', {'running': _running});
    }
  }

  static Future<void> _run() async {
    // A sheet on top (the enterprise switcher) is closed first.
    if (Get.rawRoute is! GetPageRoute) Get.back<void>();
    // The home screen is the route on top once the sheet is gone.
    final homes = <Route<dynamic>>{
      ...observer.routes,
      ?homeBelow,
      if (observer.routes.isEmpty && homeBelow == null) ?Get.rawRoute,
    };
    homeBelow = null;
    // A focused field (keyboard open) is released before its screen goes, or
    // the new screen's fields cannot take focus afterwards.
    final hadFocus =
        FocusManager.instance.primaryFocus != null &&
        FocusManager.instance.primaryFocus != FocusManager.instance.rootScope;
    FocusManager.instance.primaryFocus?.unfocus();
    if (hadFocus) await Future<void>.delayed(const Duration(milliseconds: 350));
    final retire = retireHome;
    retireHome = null;
    final open = overlays.values.toList();
    await WidgetsBinding.instance.endOfFrame;
    if (retire != null || open.isNotEmpty) {
      retire?.call();
      for (final overlay in open) {
        overlay.retire();
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    for (final overlay in open) {
      overlay.close();
    }
    homes.forEach(RouterReportManager.reportRouteDispose);
    Get.offAllNamed(AppRoutes.chats);
    await WidgetsBinding.instance.endOfFrame;
  }
}

/// The home routes (one per tab route) that are in the stack.
class _HomeObserver extends NavigatorObserver {
  static const _names = {
    AppRoutes.chats,
    AppRoutes.aiAgents,
    AppRoutes.submissions,
    AppRoutes.profile,
  };

  final routes = <Route<dynamic>>{};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_names.contains(route.settings.name)) routes.add(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    routes.remove(oldRoute);
    if (newRoute != null && _names.contains(newRoute.settings.name)) {
      routes.add(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
}
