import 'package:flutter/widgets.dart';

import 'crash_breadcrumbs.dart';
import 'crash_service.dart';

/// The route name without arguments: `/conversation/abc` is `/conversation`;
/// `/debug/...` and `/gallery/...` keep their second part.
String crashScreenName(String? route) {
  final parts = (route ?? '').split('?').first.split('/')
    ..removeWhere((p) => p.isEmpty);
  if (parts.isEmpty) return '/';
  final keepsTwo =
      parts.length > 1 && (parts[0] == 'debug' || parts[0] == 'gallery');
  return '/${keepsTwo ? '${parts[0]}/${parts[1]}' : parts[0]}';
}

class CrashRouteObserver extends NavigatorObserver {
  void _seen(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    final screen = crashScreenName(name);
    CrashBreadcrumbs.add(Crumb.screen, code: screen);
    CrashService.key('screen', screen);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _seen(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _seen(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _seen(previousRoute);
}
