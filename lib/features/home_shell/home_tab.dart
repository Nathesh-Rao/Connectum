import '../../core/routes/app_routes.dart';

/// The tabs of the home, in bottom-bar order. Code addresses a tab by this
/// name, never by a number.
enum HomeTab {
  chats(AppRoutes.chats, 'Chats'),
  smartView(AppRoutes.smartView, 'Smart view'),
  inbox(AppRoutes.inbox, 'Inbox'),
  agents(AppRoutes.aiAgents, 'Agents'),
  submits(AppRoutes.submissions, 'Submits');

  const HomeTab(this.route, this.label);

  final String route;

  /// The name on the bottom bar.
  final String label;

  static HomeTab? ofRoute(String? route) {
    for (final t in values) {
      if (t.route == route) return t;
    }
    return null;
  }
}
