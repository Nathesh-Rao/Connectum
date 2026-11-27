import 'package:flutter/material.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../tour_gesture.dart';
import '../tour_texts.dart';
import 'tour_gesture_hint.dart';
import 'tour_pointer.dart';

/// What the person chose in [TourIntroDialog].
enum TourIntroChoice { show, skip }

/// The one-time intro before the first tour that uses sample data. The
/// barrier and back do nothing: only a button closes it, so the choice is
/// never made by accident.
class TourIntroDialog extends StatefulWidget {
  const TourIntroDialog({super.key, required this.isReduced});

  static const double maxWidth = 340;
  static const double headerHeight = 84;

  final bool isReduced;

  static Future<TourIntroChoice> show(BuildContext context) async {
    final isReduced = MediaQuery.disableAnimationsOf(context);
    final choice = await showGeneralDialog<TourIntroChoice>(
      context: context,
      barrierDismissible: false,
      barrierLabel: TourTexts.introTitle,
      barrierColor: AppColors.sheetBackdrop,
      transitionDuration: isReduced ? Duration.zero : AppDurations.base,
      pageBuilder: (_, _, _) => TourIntroDialog(isReduced: isReduced),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppCurves.out);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    return choice ?? TourIntroChoice.show;
  }

  @override
  State<TourIntroDialog> createState() => _TourIntroDialogState();
}

class _TourIntroDialogState extends State<TourIntroDialog> {
  static const _gestures = [
    (TourGesture.tap, Icons.touch_app_outlined),
    (TourGesture.longPress, Icons.ads_click),
    (TourGesture.swipeLeft, Icons.swipe_left_alt),
  ];
  static const _tones = [AppTones.primary, AppTones.violet, AppTones.teal];
  static const _pause = Duration(milliseconds: 500);
  static const _tag = 'tour_intro';

  final _pointer = TourPointerController();
  final _keys = [for (final _ in _gestures) GlobalKey()];
  int _active = 0;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    if (!widget.isReduced) {
      _isRunning = true;
      fireAndLog(_tag, _loop);
    }
  }

  Future<void> _loop() async {
    await WidgetsBinding.instance.endOfFrame;
    while (_isRunning && mounted) {
      final box = _keys[_active].currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        await _pointer.play(
          box.localToGlobal(Offset.zero) & box.size,
          _gestures[_active].$1,
          isReduced: false,
        );
      }
      if (!_isRunning || !mounted) return;
      await Future<void>.delayed(_pause);
      if (!_isRunning || !mounted) return;
      await _pointer.hide();
      if (!_isRunning || !mounted) return;
      setState(() => _active = (_active + 1) % _gestures.length);
    }
  }

  @override
  void dispose() {
    _isRunning = false;
    super.dispose();
  }

  void _close(TourIntroChoice choice) => Navigator.of(context).pop(choice);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        namesRoute: true,
        label: TourTexts.introTitle,
        child: Dialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(AppSpacing.md),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.sheet)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: TourIntroDialog.maxWidth,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          TourTexts.introTitle,
                          style: AppText.heading,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          TourTexts.introBody,
                          style: AppText.body.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Semantics(
                          button: true,
                          label: TourTexts.introStartLabel,
                          excludeSemantics: true,
                          child: AppButton.primary(
                            label: TourTexts.introStart,
                            onPressed: () => _close(TourIntroChoice.show),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Semantics(
                          button: true,
                          label: TourTexts.introSkipLabel,
                          excludeSemantics: true,
                          child: AppButton.text(
                            label: TourTexts.introSkip,
                            onPressed: () => _close(TourIntroChoice.skip),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return ExcludeSemantics(
      child: SizedBox(
        height: TourIntroDialog.headerHeight,
        child: ColoredBox(
          color: AppTones.primary.tint,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _gestures.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      _chip(i),
                    ],
                  ],
                ),
              ),
              if (!widget.isReduced)
                Positioned.fill(child: TourPointer(controller: _pointer)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(int i) {
    final tone = _tones[i];
    final isActive = widget.isReduced || i == _active;
    return AnimatedOpacity(
      duration: widget.isReduced ? Duration.zero : AppDurations.base,
      opacity: isActive ? 1 : 0.5,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        ),
        child: Padding(
          key: _keys[i],
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: widget.isReduced
              ? SizedBox(
                  width: TourGestureHint.width,
                  height: TourGestureHint.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tone.tint,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadius.control),
                      ),
                    ),
                    child: Icon(_gestures[i].$2, size: 20, color: tone.strong),
                  ),
                )
              : TourGestureHint(
                  gesture: _gestures[i].$1,
                  tone: tone,
                  isReduced: !isActive,
                ),
        ),
      ),
    );
  }
}
