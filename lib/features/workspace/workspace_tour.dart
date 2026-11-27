import 'package:flutter/material.dart';

import '../../core/selection/selection_rules.dart';
import '../../core/theme/app_tones.dart';
import '../../core/tour/tour_action.dart';
import '../../core/tour/tour_demo.dart';
import '../../core/tour/tour_id.dart';
import '../../core/tour/tour_service.dart';
import '../../core/tour/tour_step.dart';
import '../../core/tour/tour_texts.dart';
import '../../core/widgets/message_selection/swipe_to_reply.dart';
import '../../data/models/message.dart';
import 'workspace_tour_demo.dart';

/// The first-run tour of My Work Space: five steps. The keys are put on the
/// screen's own widgets by the view. With no note on the screen, [demo] shows
/// one sample note for the length of the tour.
class WorkspaceTour {
  WorkspaceTour({required this.service});

  final TourService service;
  final demo = WorkspaceTourDemo();

  final headerKey = GlobalKey(debugLabel: 'tour-ws-header');
  final composerKey = GlobalKey(debugLabel: 'tour-ws-composer');

  /// The feed. It stays mounted while the header is swapped for the selection
  /// bar, so the tour runs in its context.
  final areaKey = GlobalKey(debugLabel: 'tour-ws-area');

  /// The note the tour presses and holds (real or sample).
  final noteKey = GlobalKey(debugLabel: 'tour-ws-note');

  /// The row the tour slides to the right (real or sample).
  final swipeKey = GlobalKey<SwipeToReplyState>(debugLabel: 'tour-ws-swipe');
  final selectionBarKey = GlobalKey(debugLabel: 'tour-ws-selection-bar');

  String? _holdId;
  void Function(String id)? _selectReal;
  VoidCallback? _clearReal;
  SelectionTarget? _realTarget;
  bool _didSelectReal = false;

  /// The real note to press and hold: the newest one.
  static Message? holdNote(Iterable<Message> notes) => notes.firstOrNull;

  /// The real note to slide: the newest one that can be replied to.
  static Message? swipeNote(
    Iterable<Message> notes,
    SelectionTarget Function(Message m) targetOf,
  ) {
    for (final m in notes) {
      if (targetOf(m).canReply) return m;
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

  TourAction _select() => TourAction(
    kind: TourActionKind.longPressRow,
    target: noteKey,
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

  static String _label(SelectionAction a) => switch (a) {
    SelectionAction.retry => 'Retry',
    SelectionAction.reply => 'Reply',
    SelectionAction.star => 'Save',
    SelectionAction.delete => 'Delete',
    SelectionAction.copy => 'Copy',
    SelectionAction.pin => 'Pin',
    SelectionAction.edit => 'Edit',
    SelectionAction.forward => 'Forward',
    SelectionAction.formMenu => 'Form actions',
  };

  /// With one of my notes on screen the note steps point at it; without one
  /// they point at the sample note.
  List<TourStep> steps({required bool hasNote}) {
    final target = (hasNote ? _realTarget : null) ?? WorkspaceTourDemo.target;
    final actions = SelectionRules.available([target])
        .where(
          (a) => a != SelectionAction.forward && a != SelectionAction.formMenu,
        )
        .toList();
    final split = SelectionRules.split(actions, _width());
    final isSelectable = actions.isNotEmpty;
    return [
      TourStep(
        target: headerKey,
        icon: Icons.work_outline,
        title: TourTexts.wsHeaderTitle,
        body: TourTexts.wsHeaderBody,
        tone: AppTones.primary,
      ),
      TourStep(
        target: composerKey,
        icon: Icons.edit_note,
        title: TourTexts.wsComposerTitle,
        body: TourTexts.wsComposerBody,
        tone: AppTones.teal,
      ),
      if (target.canReply)
        TourStep(
          target: swipeKey,
          icon: Icons.reply,
          title: TourTexts.wsSwipeTitle,
          body: TourTexts.wsSwipeBody,
          tone: AppTones.green,
          isAllowed: () => TourService.isVisible(swipeKey),
          actions: [_swipe()],
        ),
      if (isSelectable)
        TourStep(
          target: noteKey,
          icon: Icons.push_pin_outlined,
          title: TourTexts.wsHoldTitle,
          body: TourTexts.wsHoldBody,
          tone: AppTones.indigo,
          isAllowed: () => TourService.isVisible(noteKey),
          actions: [_select()],
        ),
      if (isSelectable)
        TourStep(
          target: selectionBarKey,
          icon: Icons.checklist,
          title: TourTexts.wsOptionsTitle,
          body: TourTexts.optionsBody(
            [for (final a in split.icons) _label(a)],
            [for (final a in split.overflow) _label(a)],
            note: actions.contains(SelectionAction.edit)
                ? TourTexts.wsEditNote
                : null,
          ),
          tone: AppTones.primary,
          isAllowed: () => TourService.isVisible(noteKey),
          actions: [_select()],
          side: TourSide.below,
        ),
    ];
  }

  /// Starts the tour once the first-run tour of the chat list has been seen.
  /// [holdId] is the real note to press and hold ([target] is what it
  /// allows, [select] and [clear] change the real selection); without a note
  /// the sample is used.
  Future<TourStart> start({
    required bool hasNote,
    String? holdId,
    SelectionTarget? target,
    void Function(String id)? select,
    VoidCallback? clear,
  }) async {
    final context = areaKey.currentContext;
    if (context == null || !context.mounted) return TourStart.blocked;
    _holdId = holdId;
    _realTarget = target;
    _selectReal = select;
    _clearReal = clear;
    demo.prepare(hasRealNote: hasNote);
    return service.start(
      TourId.workspace,
      steps(hasNote: hasNote),
      context: context,
      after: TourId.chatList,
      demo: TourDemo(seed: demo.seed, restore: demo.restore),
    );
  }

  void cancel() {
    if (service.activeId == TourId.workspace) service.cancel();
  }
}
