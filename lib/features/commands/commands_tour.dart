import 'package:flutter/material.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';

/// The `#` shortcuts tour of one composer: it starts once the person has
/// typed `#`, paused for a moment and the list of commands is still showing.
/// It never takes typing away: the next keystroke, or the list closing,
/// ends it without marking it as seen, and it does not start again until the
/// list has been closed and reopened.
class CommandsTour {
  CommandsTour({
    required this.service,
    required this.isListOpen,
    this.hasRows = _always,
    Duration settle = const Duration(milliseconds: 700),
  }) {
    _trigger = TourTrigger(
      canTry: isListOpen,
      start: _start,
      settle: settle,
      retry: const Duration(seconds: 1),
      maxTries: 5,
    );
  }

  static const _tag = 'commands_tour';

  final TourService service;

  /// True while the list of command names shows (not a command's arguments).
  final bool Function() isListOpen;

  /// True once the list has commands in it (not while it says "Loading").
  final bool Function() hasRows;

  static bool _always() => true;

  final panelKey = GlobalKey(debugLabel: 'tour-commands-panel');
  final inboxKey = GlobalKey(debugLabel: 'tour-commands-inbox');
  final viewKey = GlobalKey(debugLabel: 'tour-commands-view');
  final sendKey = GlobalKey(debugLabel: 'tour-commands-send');

  late final TourTrigger _trigger;
  bool _isShownThisOpen = false;

  /// The key of a command's row in the list, for the two examples.
  GlobalKey? rowKeyOf(String name) => switch (name) {
    'inbox' => inboxKey,
    'view' => viewKey,
    _ => null,
  };

  /// The person typed in the box (and the list was updated for it).
  void onTyped() {
    if (service.activeId == TourId.commands) {
      service.cancel();
      _isShownThisOpen = true;
    }
    _trigger.cancel();
    if (!isListOpen()) {
      _isShownThisOpen = false;
      return;
    }
    if (!_isShownThisOpen) _trigger.schedule();
  }

  /// The list opened or closed without typing (back, a pick).
  void onListChanged() {
    if (isListOpen()) return;
    _trigger.cancel();
    _isShownThisOpen = false;
    if (service.activeId == TourId.commands) service.cancel();
  }

  void dispose() {
    _trigger.dispose();
    if (service.activeId == TourId.commands) service.cancel();
  }

  bool _isInPanel(GlobalKey row) =>
      safeSync(_tag, () {
        final panel = panelKey.currentContext?.findRenderObject();
        final box = row.currentContext?.findRenderObject();
        if (panel is! RenderBox || box is! RenderBox) return false;
        if (!panel.attached || !box.attached) return false;
        final outer = panel.localToGlobal(Offset.zero) & panel.size;
        final inner = box.localToGlobal(Offset.zero) & box.size;
        // A row fills the panel's width, so its edges touch the panel's.
        final roomy = outer.inflate(1);
        return roomy.contains(inner.topLeft) &&
            roomy.contains(inner.bottomRight);
      }) ??
      false;

  /// The steps for what the list shows now: the panel, one example row that
  /// is really in view, and the send button.
  List<TourStep> steps() => [
    TourStep(
      target: panelKey,
      icon: Icons.tag,
      title: TourTexts.cmdPanelTitle,
      body: TourTexts.cmdPanelBody,
      tone: AppTones.violet,
    ),
    TourStep(
      target: inboxKey,
      icon: Icons.inbox_outlined,
      title: TourTexts.cmdInboxTitle,
      body: TourTexts.cmdInboxBody,
      tone: AppTones.teal,
      isAllowed: () => _isInPanel(inboxKey),
    ),
    TourStep(
      target: viewKey,
      icon: Icons.table_chart_outlined,
      title: TourTexts.cmdViewTitle,
      body: TourTexts.cmdViewBody,
      tone: AppTones.teal,
      isAllowed: () => !_isInPanel(inboxKey) && _isInPanel(viewKey),
    ),
    TourStep(
      target: sendKey,
      icon: Icons.arrow_upward,
      title: TourTexts.cmdRunTitle,
      body: TourTexts.cmdRunBody,
      tone: AppTones.green,
      shape: TourShape.circle,
      gesture: TourGesture.tap,
    ),
  ];

  Future<TourStart> _start() async {
    final context = panelKey.currentContext;
    if (context == null || !context.mounted || !isListOpen() || !hasRows()) {
      return TourStart.blocked;
    }
    final result = await service.start(
      TourId.commands,
      steps(),
      context: context,
      allowKeyboard: true,
    );
    if (result == TourStart.started) _isShownThisOpen = true;
    return result;
  }
}
