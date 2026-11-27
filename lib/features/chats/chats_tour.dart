import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import '../home_shell/home_tab.dart';

/// The first-run tour of the chat list: its targets and its six or seven steps. The
/// keys are put on the screen's own widgets by the view.
class ChatsTour {
  ChatsTour({
    required this.service,
    required this.tabsKey,
    this.tabs = HomeTab.values,
  });

  final TourService service;

  /// The bottom bar, owned by the home shell.
  final GlobalKey tabsKey;

  /// The tabs this person can use, in bar order. All of them today: the app
  /// has no per-tab permission yet.
  final List<HomeTab> tabs;

  final headerKey = GlobalKey(debugLabel: 'tour-chats-header');
  final switcherKey = GlobalKey(debugLabel: 'tour-chats-switcher');
  final actionsKey = GlobalKey(debugLabel: 'tour-chats-actions');
  final searchKey = GlobalKey(debugLabel: 'tour-chats-search');
  final newChatKey = GlobalKey(debugLabel: 'tour-chats-new');
  final workspaceKey = GlobalKey(debugLabel: 'tour-chats-workspace');
  final firstRowKey = GlobalKey(debugLabel: 'tour-chats-row');

  /// The steps, top to bottom. My Work Space is always there (it is pinned
  /// above the list in every state); the long-press step needs a chat, so a
  /// person with no chats gets no chat step at all.
  List<TourStep> steps({required bool isEmpty}) => [
    TourStep(
      target: switcherKey,
      icon: Icons.business_outlined,
      title: TourTexts.chatSwitcherTitle,
      body: TourTexts.chatSwitcherBody,
      tone: AppTones.primary,
    ),
    TourStep(
      target: actionsKey,
      icon: Icons.notifications_none,
      title: TourTexts.chatActionsTitle,
      body: TourTexts.chatActionsBody,
      tone: AppTones.primary,
    ),
    TourStep(
      target: searchKey,
      icon: Icons.search,
      title: TourTexts.chatSearchTitle,
      body: TourTexts.chatSearchBody,
      tone: AppTones.teal,
    ),
    TourStep(
      target: workspaceKey,
      icon: Icons.work_outline,
      title: TourTexts.chatWorkspaceTitle,
      body: TourTexts.chatWorkspaceBody,
      tone: AppTones.green,
    ),
    if (!isEmpty)
      TourStep(
        target: firstRowKey,
        icon: Icons.chat_bubble_outline,
        title: TourTexts.chatRowTitle,
        body: TourTexts.chatRowBody,
        tone: AppTones.green,
        gesture: TourGesture.longPress,
      ),
    TourStep(
      target: newChatKey,
      icon: Icons.add_comment_outlined,
      title: TourTexts.chatNewTitle,
      body: TourTexts.chatNewBody,
      tone: AppTones.violet,
      shape: TourShape.circle,
    ),
    TourStep(
      target: tabsKey,
      icon: Icons.dashboard_customize_outlined,
      title: TourTexts.chatTabsTitle,
      body: TourTexts.chatTabsBody([for (final t in tabs) t.label]),
      tone: AppTones.indigo,
    ),
  ];

  /// Starts the tour on the chat list. The header's context is the one inside
  /// this screen's route.
  Future<TourStart> start({required bool isEmpty}) async {
    final context = headerKey.currentContext;
    if (context == null || !context.mounted) return TourStart.blocked;
    return service.start(
      TourId.chatList,
      steps(isEmpty: isEmpty),
      context: context,
    );
  }

  void cancel() => service.cancel();
}
