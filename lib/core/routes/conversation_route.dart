import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'app_routes.dart';
import 'home_reload.dart';

/// Opening a conversation. Two routes for the same conversation would share a
/// controller (one per conversation id), so a conversation that is already
/// the top route is left alone and one deeper in the stack is popped back to.
class ConversationRoute {
  ConversationRoute._();

  static final observer = _StackObserver();

  static final _jumps = <String, String>{};

  /// An open conversation's hook that scrolls to a waiting message.
  static final jumpListeners = <String, void Function()>{};

  /// Asks the conversation to scroll to [messageId] and flash it once it is
  /// open (or at once, when it already is).
  static void jumpTo(String conversationId, String messageId) {
    _jumps[conversationId] = messageId;
    jumpListeners[conversationId]?.call();
  }

  static String? takeJump(String conversationId) =>
      _jumps.remove(conversationId);

  static final _drafts = <String, String>{};

  /// Text a `#dm` or `#groupmsg` leaves in the box of [conversationId]; the
  /// conversation takes it once, when it opens. Never sent from here.
  static void setDraft(String conversationId, String text) {
    if (text.isNotEmpty) _drafts[conversationId] = text;
  }

  static String? takeDraft(String conversationId) =>
      _drafts.remove(conversationId);

  static void open(String conversationId) {
    final name = AppRoutes.conversationOf(conversationId);
    if (Get.currentRoute == name) return;
    if (observer.names.contains(name)) {
      Get.until((route) => route.settings.name == name);
      return;
    }
    // A reload that starts while conversations are open has to take the home
    // down too, so the home route is noted before the first one is pushed.
    if (observer.names.isEmpty && Get.rawRoute is GetPageRoute) {
      HomeReload.homeBelow = Get.rawRoute;
    }
    Get.toNamed(name);
  }
}

/// Knows which conversation routes are in the stack (pushed and not yet
/// popped), from the moment each is pushed to the moment it starts to leave.
class _StackObserver extends NavigatorObserver {
  final names = <String>[];

  bool _isConversation(Route<dynamic>? route) =>
      route?.settings.name?.startsWith('/conversation/') ?? false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isConversation(route)) names.add(route.settings.name!);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _left(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _left(route);

  void _left(Route<dynamic> route) {
    if (!_isConversation(route)) return;
    names.remove(route.settings.name);
    if (names.isEmpty) HomeReload.homeBelow = null;
  }
}
