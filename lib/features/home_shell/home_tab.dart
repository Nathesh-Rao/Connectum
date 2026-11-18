import '../../core/routes/app_routes.dart';

/// The tabs of the home, in bottom-bar order. Code addresses a tab by this
/// name, never by a number.
enum HomeTab {
  chats(AppRoutes.chats),
  smartView(AppRoutes.smartView),
  inbox(AppRoutes.inbox),
  agents(AppRoutes.aiAgents),
  submits(AppRoutes.submissions);

  const HomeTab(this.route);

  final String route;

  static HomeTab? ofRoute(String? route) {
    for (final t in values) {
      if (t.route == route) return t;
    }
    return null;
  }
}
