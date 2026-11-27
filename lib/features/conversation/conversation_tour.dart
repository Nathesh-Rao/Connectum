import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/selection/selection_rules.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import 'conversation_tour_demo.dart';
import 'models/chat_item.dart';

/// What this chat lets the person do, read when the tour starts. The steps
/// are built from it, so a step for something the chat cannot do is never
/// shown.
class ConversationTourCaps {
  const ConversationTourCaps({
    this.isEncrypted = false,
    this.isBlocked = false,
    this.isDirect = true,
    this.canAttach = false,
    this.canReact = false,
    this.canEdit = false,
    this.canReply = false,
    this.canDelete = false,
    this.holdTarget,
  });

  /// End-to-end encrypted: the lock shows, and `#` is not sent.
  final bool isEncrypted;

  /// The composer is replaced by a note saying why nothing can be sent.
  final bool isBlocked;
  final bool isDirect;
  final bool canAttach;
  final bool canReact;

  /// Own text messages can be edited (for 15 minutes).
  final bool canEdit;
  final bool canReply;
  final bool canDelete;

  /// What the real message the tour will select allows (the controller's
  /// `targetOf`); null when the chat has no message and the sample is used.
  final SelectionTarget? holdTarget;
}

/// The first-chat tour: its targets and at most six steps. The keys are put
/// on the conversation screen's own widgets by the view. With no message in
/// the chat, [demo] shows two sample messages for the length of the tour.
class ConversationTour {
  ConversationTour({required this.service});

  final TourService service;
  final demo = ConversationTourDemo();

  final headerKey = GlobalKey(debugLabel: 'tour-chat-header');
  final composerKey = GlobalKey(debugLabel: 'tour-chat-composer');

  /// The message area. It stays mounted while the header is swapped for the
  /// selection bar, so the tour runs in its context.
  final areaKey = GlobalKey(debugLabel: 'tour-chat-area');

  /// The message the tour presses and holds (real or sample).
  final messageKey = GlobalKey(debugLabel: 'tour-chat-message');

  /// The row the tour slides to the right (real or sample).
  final swipeKey = GlobalKey<SwipeToReplyState>(debugLabel: 'tour-chat-swipe');
  final reactionKey = GlobalKey(debugLabel: 'tour-chat-reactions');
  final selectionBarKey = GlobalKey(debugLabel: 'tour-chat-selection-bar');

  String? _holdId;
  void Function(String id)? _selectReal;
  VoidCallback? _clearReal;
  bool _didSelectReal = false;

  /// A message the tour may point at: text, not a form, not deleted.
  static bool isOrdinary(ChatItem i) =>
      i.kind == ChatItemKind.message &&
      i.message != null &&
      i.message!.kind != 'form' &&
      !i.message!.isDeleted;

  /// The real message to press and hold: the newest of mine that can be
  /// deleted (so Edit and Delete show), else the newest one.
  static Message? holdMessage(
    List<ChatItem> items,
    SelectionTarget Function(Message m) targetOf,
  ) {
    final ordinary = [
      for (final i in items)
        if (isOrdinary(i)) i.message!,
    ];
    return ordinary.firstWhereOrNull(
          (m) => m.isMine && targetOf(m).canDelete,
        ) ??
        ordinary.firstOrNull;
  }

  /// The real message to slide: the newest one that can be replied to.
  static Message? swipeMessage(
    List<ChatItem> items,
    SelectionTarget Function(Message m) targetOf,
  ) {
    for (final i in items) {
      if (isOrdinary(i) && targetOf(i.message!).canReply) return i.message;
    }
    return null;
  }

  bool _isReduced() {
    final context = headerKey.currentContext;
    return context != null &&
        context.mounted &&
        MediaQuery.disableAnimationsOf(context);
  }

  double _width() {
    final context = headerKey.currentContext;
    if (context == null || !context.mounted) return 400;
    return MediaQuery.sizeOf(context).width;
  }

  TourAction _swipe() => TourAction(
    kind: TourActionKind.swipeRow,
    target: swipeKey,
    run: () => swipeKey.currentState?.peek(isReduced: _isReduced()),
    undo: () => swipeKey.currentState?.reset(),
  );

  /// Selects the message; the next step carries it on ([TourAction.carry]).
  TourAction _select() => TourAction(
    kind: TourActionKind.longPressRow,
    target: messageKey,
    carry: 'select',
    run: () {
      if (demo.isOn.value) {
        demo.select();
        return;
      }
      final id = _holdId;
      if (id == null) return;
      _didSelectReal = true;
      _selectReal?.call(id);
    },
    undo: () {
      demo.clearSelection();
      if (_didSelectReal) _clearReal?.call();
      _didSelectReal = false;
    },
  );

  /// With a real message on screen the message steps point at it; without
  /// one they point at the two sample messages.
  List<TourStep> steps(ConversationTourCaps caps, {required bool hasMessage}) {
    final target =
        (hasMessage ? caps.holdTarget : null) ??
        ConversationTourDemo.targetOf(caps);
    final actions = SelectionRules.available([
      target,
    ], isEditIcon: true).where(_isShown).toList();
    final split = SelectionRules.split(actions, _width(), isEditIcon: true);
    final bar = [for (final a in split.icons) _label(a)];
    final more = [for (final a in split.overflow) _label(a)];
    final isSelectable = actions.isNotEmpty;
    return [
      TourStep(
        target: headerKey,
        icon: Icons.info_outline,
        title: TourTexts.chatInfoTitle,
        body: caps.isEncrypted
            ? TourTexts.chatInfoLockedBody
            : TourTexts.chatInfoBody,
        tone: AppTones.primary,
      ),
      if (!caps.isBlocked)
        TourStep(
          target: composerKey,
          icon: Icons.edit_outlined,
          title: TourTexts.chatComposerTitle,
          body: TourTexts.chatComposerBody(canAttach: caps.canAttach),
          tone: AppTones.teal,
        ),
      if (!caps.isBlocked && !caps.isEncrypted)
        TourStep(
          target: composerKey,
          icon: Icons.tag,
          title: TourTexts.chatHashTitle,
          body: TourTexts.chatHashBody,
          tone: AppTones.violet,
          gesture: TourGesture.typeHash,
        ),
      if (caps.canReply)
        TourStep(
          target: swipeKey,
          icon: Icons.reply,
          title: TourTexts.chatSwipeTitle,
          body: TourTexts.chatSwipeBody,
          tone: AppTones.green,
          isAllowed: () => TourService.isVisible(swipeKey),
          actions: [_swipe()],
        ),
      if (isSelectable)
        TourStep(
          target: target.canReact ? reactionKey : messageKey,
          icon: Icons.touch_app_outlined,
          title: TourTexts.chatHoldTitle,
          body: TourTexts.chatHoldBody(canReact: target.canReact),
          tone: AppTones.indigo,
          isAllowed: () => TourService.isVisible(messageKey),
          actions: [_select()],
          side: target.canReact ? TourSide.above : TourSide.auto,
        ),
      if (isSelectable)
        TourStep(
          target: selectionBarKey,
          icon: Icons.checklist,
          title: TourTexts.chatOptionsTitle,
          body: TourTexts.optionsBody(
            bar,
            more,
            note: actions.contains(SelectionAction.edit)
                ? TourTexts.editWindowNote
                : null,
          ),
          tone: AppTones.primary,
          isAllowed: () => TourService.isVisible(messageKey),
          actions: [_select()],
          side: TourSide.below,
        ),
    ];
  }

  /// The chat's selection bar has no save or pin of a message.
  static bool _isShown(SelectionAction a) =>
      a != SelectionAction.star && a != SelectionAction.pin;

  static String _label(SelectionAction a) => switch (a) {
    SelectionAction.retry => 'Retry',
    SelectionAction.reply => 'Reply',
    SelectionAction.edit => 'Edit',
    SelectionAction.delete => 'Delete',
    SelectionAction.forward => 'Forward',
    SelectionAction.copy => 'Copy',
    SelectionAction.formMenu => 'Form actions',
    SelectionAction.star => 'Save',
    SelectionAction.pin => 'Pin',
  };

  /// Starts the tour once the first-run tour of the chat list has been seen.
  /// [holdId] is the real message to press and hold ([select] and [clear]
  /// change the real selection); with [hasMessage] false the sample is used.
  Future<TourStart> start(
    ConversationTourCaps caps, {
    required bool hasMessage,
    String? holdId,
    void Function(String id)? select,
    VoidCallback? clear,
  }) async {
    final context = areaKey.currentContext;
    if (context == null || !context.mounted) return TourStart.blocked;
    _holdId = holdId;
    _selectReal = select;
    _clearReal = clear;
    demo.prepare(caps, hasRealMessage: hasMessage);
    return service.start(
      TourId.chat,
      steps(caps, hasMessage: hasMessage),
      context: context,
      after: TourId.chatList,
      demo: TourDemo(seed: demo.seed, restore: demo.restore),
    );
  }

  void cancel() {
    if (service.activeId == TourId.chat) service.cancel();
  }
}
