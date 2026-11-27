import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../log/app_log.dart';
import '../log/safe.dart';
import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import 'tour_demo.dart';
import 'tour_id.dart';
import 'tour_runner.dart';
import 'tour_step.dart';
import 'tour_store.dart';
import 'tour_texts.dart';
import 'widgets/tour_card.dart';
import 'widgets/tour_card_layer.dart';
import 'widgets/tour_intro_dialog.dart';
import 'widgets/tour_pointer.dart';

/// Why [TourService.start] did or did not show a tour. [notReady] means the
/// tour it has to wait for (`after`) has not been seen yet on this account.
enum TourStart { started, seen, notReady, tooFewSteps, blocked, busy, failed }

/// Runs the first-run tours. Screens use this and never the package behind it.
/// One tour at a time; a tour that is interrupted (back, tab or route change,
/// app pause, a sheet or the keyboard appearing) is not marked as seen, one
/// that is finished or skipped is. Nothing here throws.
class TourService extends GetxService with WidgetsBindingObserver {
  TourService({
    required String? Function() userId,
    TourStore? store,
    List<bool Function()> blockers = const [],
    List<String> blockerNames = const [],
    String? Function()? route,
    DateTime Function()? now,
  }) : _userId = userId,
       _store = store ?? TourStore(),
       _blockers = blockers,
       _blockerNames = blockerNames,
       _route = route ?? (() => Get.currentRoute),
       _now = now ?? DateTime.now;

  static const _tag = 'tour_service';
  static const _padding = 16.0;
  static const _shadowOpacity = 0.72;
  static const _watchEvery = Duration(milliseconds: 400);
  static const _maxBuildFrames = 30;

  final String? Function() _userId;
  final TourStore _store;
  final List<bool Function()> _blockers;
  final List<String> _blockerNames;
  final String? Function() _route;
  final DateTime Function() _now;
  final _lastLog = <TourId, (String, DateTime)>{};
  String _why = '';

  /// True from the moment a tour is accepted until it ends.
  final isActive = false.obs;

  TutorialCoachMark? _coach;
  BuildContext? _context;
  TourId? _id;
  bool _allowKeyboard = false;
  Timer? _watch;
  bool _isStarting = false;
  bool _isObserving = false;
  bool _isAdvancing = false;
  TourRunner? _runner;

  /// The bottom navigation bar, set by the screen that has one. A card never
  /// goes over it.
  GlobalKey? bottomBarKey;

  /// The tour on screen, or null.
  TourId? get activeId => isActive.value ? _id : null;

  Future<bool> isSeen(TourId id) async {
    final user = _userId();
    if (user == null) return false;
    return _store.isSeen(user, id);
  }

  Future<void> markSeen(TourId id) async {
    final user = _userId();
    if (user == null) return;
    await _store.markSeen(user, id);
  }

  Future<void> reset(TourId id) async {
    final user = _userId();
    if (user == null) return;
    await _store.reset(user, id);
  }

  /// Every tour and the intro dialog play again.
  Future<void> resetAll() async {
    final user = _userId();
    if (user != null) await _store.resetIntro(user);
    for (final id in TourId.values) {
      await reset(id);
    }
  }

  /// [after] is a tour that must have been finished or skipped first (on
  /// this account); until then nothing starts. [allowKeyboard] is for a tour
  /// that points at what the person is typing in: it may start, and stay,
  /// while the keyboard is open.
  Future<TourStart> start(
    TourId id,
    List<TourStep> steps, {
    required BuildContext context,
    TourId? after,
    bool allowKeyboard = false,
    TourDemo? demo,
  }) async {
    final result = await _start(id, steps, context, after, allowKeyboard, demo);
    _log(id, result);
    return result;
  }

  Future<TourStart> _start(
    TourId id,
    List<TourStep> steps,
    BuildContext context,
    TourId? after,
    bool allowKeyboard,
    TourDemo? demo,
  ) async {
    _why = '';
    if (isActive.value || _isStarting) {
      _why = 'tour:${_id?.name} active';
      return TourStart.busy;
    }
    _isStarting = true;
    TourRunner? runner;
    var isStarted = false;
    try {
      final user = _userId();
      if (user == null) {
        _why = 'no user';
        return TourStart.blocked;
      }
      if (await _store.isSeen(user, id)) return TourStart.seen;
      if (after != null && !await _store.isSeen(user, after)) {
        _why = 'after:${after.name} not seen';
        return TourStart.notReady;
      }
      if (isActive.value) {
        _why = 'tour:${_id?.name} active';
        return TourStart.busy;
      }
      if (!context.mounted) {
        _why = 'context unmounted';
        return TourStart.blocked;
      }
      final blockedBy = _blockedBy(context, allowKeyboard);
      if (blockedBy != null) {
        _why = blockedBy;
        return TourStart.blocked;
      }
      runner = TourRunner(
        demo: demo,
        pointer: demo == null && steps.every((s) => s.actions.isEmpty)
            ? null
            : TourPointerHost(context),
        isReduced: MediaQuery.disableAnimationsOf(context),
      );
      // The sample goes in before the targets are counted, and is always put
      // back when the tour does not start.
      final isSample = runner.seed();
      if (isSample) {
        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) {
          _why = 'context unmounted';
          return TourStart.blocked;
        }
        final late = _blockedBy(context, allowKeyboard);
        if (late != null) {
          _why = late;
          return TourStart.blocked;
        }
      }
      var usable = _usableOf(steps);
      if (usable.length < 2) {
        _why = '${usable.length}';
        return TourStart.tooFewSteps;
      }
      if (!await _store.isIntroSeen(user)) {
        // The tour is certain to start: before the first tour a person ever
        // sees, with or without sample data, tell them first. Either button is remembered; the dialog never comes back.
        if (!context.mounted) {
          _why = 'context unmounted';
          return TourStart.blocked;
        }
        final choice = await TourIntroDialog.show(context);
        await _store.markIntroSeen(user);
        if (choice == TourIntroChoice.skip) {
          for (final tour in TourId.values) {
            await _store.markSeen(user, tour);
          }
          AppLog.i(_tag, 'tour intro: tours skipped');
          return TourStart.seen;
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) {
          _why = 'context unmounted';
          return TourStart.blocked;
        }
        final after = _blockedBy(context, allowKeyboard);
        if (after != null) {
          _why = after;
          return TourStart.blocked;
        }
        usable = _usableOf(steps);
        if (usable.length < 2) {
          _why = '${usable.length}';
          return TourStart.tooFewSteps;
        }
      }
      if (!context.mounted) {
        _why = 'context unmounted';
        return TourStart.blocked;
      }
      _allowKeyboard = allowKeyboard;
      _runner = runner;
      isStarted = true;
      await _show(id, usable, context, runner);
      return TourStart.started;
    } catch (e, st) {
      AppLog.e(_tag, e, st);
      _why = 'error';
      _end();
      return TourStart.failed;
    } finally {
      if (!isStarted) runner?.restore();
      _isStarting = false;
    }
  }

  /// One line per distinct result of an attempt; the same line again is
  /// logged at most every 10 s (retries run every 2 s).
  void _log(TourId id, TourStart result) {
    final line = switch (result) {
      TourStart.started => 'started',
      TourStart.seen => 'seen',
      TourStart.busy => 'busy',
      TourStart.tooFewSteps => 'tooFewSteps($_why)',
      TourStart.blocked => 'blocked:$_why',
      TourStart.notReady => 'notReady:$_why',
      TourStart.failed => 'blocked:$_why',
    };
    final now = _now();
    final last = _lastLog[id];
    if (last != null &&
        last.$1 == line &&
        now.difference(last.$2) < const Duration(seconds: 10)) {
      return;
    }
    _lastLog[id] = (line, now);
    AppLog.d(_tag, 'tour:${id.name} start -> $line');
  }

  /// Ends the tour for good: it is marked as seen.
  void skip() => _finish();

  /// Ends the tour because something interrupted it: not marked as seen.
  void cancel() {
    if (!isActive.value) return;
    AppLog.i(_tag, 'tour cancelled');
    _end();
  }

  // ---- checks -------------------------------------------------------------------

  /// The first rule that stops a start, named for the log; null if none.
  String? _blockedBy(BuildContext context, bool allowKeyboard) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return 'lifecycle:${lifecycle.name}';
    }
    final route = _route();
    if (isFlowRoute(route)) return 'route:$route';
    if (ModalRoute.of(context)?.isCurrent != true) {
      return 'dialog or sheet on top (route:$route)';
    }
    if (!allowKeyboard && View.of(context).viewInsets.bottom > 0) {
      return 'keyboard open';
    }
    for (var i = 0; i < _blockers.length; i++) {
      if (safeSync(_tag, _blockers[i], fallback: true) ?? true) {
        return 'blocker:${i < _blockerNames.length ? _blockerNames[i] : i}';
      }
    }
    return null;
  }

  /// Join, sign-in, onboarding and security flows: a tour never shows there.
  /// Every other screen owns its tour or is checked by the other rules.
  static bool isFlowRoute(String? route) {
    if (route == null || route.isEmpty) return false;
    const flows = [
      AppRoutes.splash,
      AppRoutes.onboarding,
      AppRoutes.authentication,
      AppRoutes.verification,
      AppRoutes.enterprises,
      AppRoutes.enterpriseCreated,
      AppRoutes.security,
    ];
    final path = route.split('?').first;
    return flows.contains(path) || path.startsWith('/connect');
  }

  List<TourStep> _usableOf(List<TourStep> steps) => [
    for (final s in steps)
      if (_isUsable(s)) s,
  ];

  bool _isUsable(TourStep step) {
    final allowed = safeSync(_tag, () => step.isAllowed?.call() ?? true);
    if (allowed != true) return false;
    if (step.actions.isNotEmpty || isVisible(step.target)) return true;
    return step.canScroll && _isBuilt(step.target);
  }

  static bool _isBuilt(GlobalKey key) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return false;
    return safeSync(_tag, () {
          final box = context.findRenderObject();
          return box is RenderBox && box.attached && box.hasSize;
        }) ??
        false;
  }

  /// A target counts when it is built, on a visible tab and at least 90 %
  /// inside the screen.
  static bool isVisible(GlobalKey key) {
    final context = key.currentContext;
    if (context == null || !context.mounted) return false;
    return safeSync(_tag, () {
          if (!TickerMode.of(context)) return false;
          final box = context.findRenderObject();
          if (box is! RenderBox || !box.attached || !box.hasSize) return false;
          if (box.size.isEmpty) return false;
          final view = View.of(context);
          final screen =
              Offset.zero & (view.physicalSize / view.devicePixelRatio);
          final rect = box.localToGlobal(Offset.zero) & box.size;
          final shown = rect.intersect(screen);
          if (shown.isEmpty) return false;
          return shown.width * shown.height >= rect.width * rect.height * 0.9;
        }) ??
        false;
  }

  // ---- showing ------------------------------------------------------------------

  Future<void> _show(
    TourId id,
    List<TourStep> steps,
    BuildContext context,
    TourRunner runner,
  ) async {
    final isReduced = MediaQuery.disableAnimationsOf(context);
    final targets = <TargetFocus>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      targets.add(
        TargetFocus(
          identify: i,
          keyTarget: step.target,
          shape: step.shape == TourShape.circle
              ? ShapeLightFocus.Circle
              : ShapeLightFocus.RRect,
          radius: AppRadius.card,
          paddingFocus: _padding,
          enableOverlayTab: false,
          enableTargetTab: false,
          borderSide: BorderSide(
            color: step.tone.solid.withValues(alpha: 0.55),
            width: 2,
          ),
          contents: [
            TargetContent(
              align: ContentAlign.custom,
              customPosition: CustomTargetContentPosition(
                top: 0,
                bottom: 0,
                left: 0,
                right: 0,
              ),
              padding: EdgeInsets.zero,
              builder: (context, controller) => TourCardLayer(
                target: step.target,
                side: step.side,
                spotPadding: _padding,
                bottomBar: () => bottomBarKey,
                child: TourCard(
                  step: step,
                  index: i,
                  total: steps.length,
                  isReduced: isReduced,
                  onNext: () {
                    HapticFeedback.lightImpact();
                    if (i == steps.length - 1) {
                      _finish();
                    } else {
                      fireAndLog(
                        _tag,
                        () => _advance(controller, id, steps, i, isReduced),
                      );
                    }
                  },
                  onSkip: skip,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final coach = TutorialCoachMark(
      targets: targets,
      colorShadow: AppColors.scrim,
      opacityShadow: _shadowOpacity,
      paddingFocus: _padding,
      hideSkip: true,
      useSafeArea: true,
      pulseEnable: !isReduced,
      focusAnimationDuration: isReduced ? Duration.zero : AppDurations.base,
      unFocusAnimationDuration: isReduced ? Duration.zero : AppDurations.base,
      pulseAnimationDuration: AppDurations.tourPulse,
      backgroundSemanticLabel: TourTexts.tourStarted,
      onFinish: cancel,
    );
    _coach = coach;
    _context = context;
    _id = id;
    isActive.value = true;
    _observe();
    _watch = Timer.periodic(_watchEvery, (_) => _check());
    AppLog.i(_tag, 'tour started: ${id.name} (${steps.length} steps)');
    // The first step acts before anything is lit, so the spotlight never
    // lands on a target that is still moving.
    if (steps.first.actions.isNotEmpty) {
      await runner.enter(null, steps.first);
      if (!isActive.value || _id != id || !context.mounted) return;
      await _untilBuilt(steps.first);
      if (!isActive.value || _id != id || !context.mounted) return;
    }
    coach.show(context: context, rootOverlay: true);
    runner.pointer?.raise();
    _announce(context, steps.first, 0, steps.length);
  }

  /// To the next step; a target that is off screen is scrolled into view
  /// first.
  Future<void> _advance(
    TutorialCoachMarkController controller,
    TourId id,
    List<TourStep> steps,
    int from,
    bool isReduced,
  ) async {
    if (_isAdvancing) return;
    _isAdvancing = true;
    try {
      final next = steps[from + 1];
      // The step acts first and settles; only then does the spotlight move.
      await _runner?.enter(steps[from], next);
      if (!isActive.value || _id != id) return;
      await _untilBuilt(next);
      if (!isActive.value || _id != id) return;
      final target = next.target.currentContext;
      if (next.canScroll &&
          target != null &&
          target.mounted &&
          !isVisible(next.target)) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: isReduced ? Duration.zero : AppDurations.base,
          curve: AppCurves.out,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!isActive.value || _id != id) return;
      controller.next();
    } finally {
      _isAdvancing = false;
    }
  }

  /// A target that an action brings up (a reaction bar, a selection bar) may
  /// need a few frames after the action; the spotlight waits for it, at most
  /// [_maxBuildFrames] frames.
  Future<void> _untilBuilt(TourStep step) async {
    if (step.actions.isEmpty) return;
    for (var i = 0; i < _maxBuildFrames; i++) {
      if (!isActive.value || _isBuilt(step.target)) return;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _announce(BuildContext context, TourStep step, int index, int total) {
    safeSync(_tag, () {
      SemanticsService.sendAnnouncement(
        View.of(context),
        TourTexts.announce(step.title, step.body, index, total),
        Directionality.of(context),
      );
    });
  }

  // ---- ending -------------------------------------------------------------------

  void _finish() {
    final id = _id;
    if (!isActive.value || id == null) return;
    fireAndLog(_tag, () => markSeen(id));
    AppLog.i(_tag, 'tour finished: ${id.name}');
    _end();
  }

  /// The one place a tour ends, whatever the reason: finish, skip, back, app
  /// pause, a route change, an error. The actions and the sample data are put
  /// back in `finally`, so nothing above can keep them from being restored.
  void _end() {
    final runner = _runner;
    _runner = null;
    try {
      _watch?.cancel();
      _watch = null;
      final coach = _coach;
      _coach = null;
      _context = null;
      _id = null;
      _allowKeyboard = false;
      _isAdvancing = false;
      isActive.value = false;
      _unobserve();
      safeSync(_tag, () => coach?.removeOverlayEntry());
    } finally {
      runner?.restore();
    }
  }

  /// Every 400 ms while a tour shows: a target that is gone, a sheet, a
  /// dialog, the keyboard or another route ends it without marking it seen.
  void _check() {
    final context = _context;
    if (!isActive.value) return;
    if (context == null || !context.mounted) return cancel();
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return cancel();
    if (!_allowKeyboard && View.of(context).viewInsets.bottom > 0) {
      return cancel();
    }
  }

  void _observe() {
    if (_isObserving) return;
    _isObserving = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void _unobserve() {
    if (!_isObserving) return;
    _isObserving = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancel();
  }

  @override
  void onClose() {
    _end();
    super.onClose();
  }
}
