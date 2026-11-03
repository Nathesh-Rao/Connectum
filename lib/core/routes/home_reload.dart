import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
// ignore: implementation_imports
import 'package:get/get_navigation/src/router_report.dart';

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

  /// Set by the home shell controller that is alive: unmounts its content.
  static VoidCallback? retireHome;

  /// The home route, noted by a screen that opens another screen over it
  /// (the enterprise switcher's "Join another enterprise"), so a reload that
  /// starts from there still takes the home down first.
  static Route<dynamic>? homeBelow;

  /// Open conversation screens: each can be unmounted and closed on its own,
  /// so a reload takes them down before the new home registers.
  static final overlays =
      <String, ({VoidCallback retire, VoidCallback close})>{};

  static Future<void> run() async {
    // A sheet on top (the enterprise switcher) is closed first.
    if (Get.rawRoute is! GetPageRoute) Get.back<void>();
    // The home screen is the route on top once the sheet is gone.
    final home = homeBelow ?? Get.rawRoute;
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
    if (home != null) RouterReportManager.reportRouteDispose(home);
    Get.offAllNamed(AppRoutes.chats);
  }
}
