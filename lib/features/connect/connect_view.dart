import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/identity_info.dart';
import 'connect_controller.dart';
import 'widgets/confirm_pane.dart';
import 'widgets/manual_pane.dart';
import 'widgets/scanner_pane.dart';
import 'widgets/status_panes.dart';

/// The body of the "Join another enterprise" sheet: one sheet that moves
/// between scanner, manual entry, the confirmation card and the results.
class ConnectView extends GetView<ConnectController> {
  const ConnectView({super.key, required this.onEnter});

  final Future<void> Function(EnterpriseMembership) onEnter;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedSize(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: Obx(() {
        final phase = c.phase.value;
        return _Fade(
          child: KeyedSubtree(
            key: ValueKey(phase),
            child: switch (phase) {
              ConnectPhase.entry => _Entry(controller: c),
              ConnectPhase.resolving => const ResolvingPane(),
              ConnectPhase.confirm => ConfirmPane(
                controller: c,
                onEnter: onEnter,
              ),
              ConnectPhase.failed => FailedPane(controller: c),
              ConnectPhase.done => DonePane(controller: c, onEnter: onEnter),
            },
          ),
        );
      }),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height:
          AppSpacing.connectPaneHeight +
          (kDebugMode ? AppSpacing.connectDebugExtra : 0),
      child: Obx(
        () => _Fade(
          child: KeyedSubtree(
            key: ValueKey(c.mode.value),
            child: c.mode.value == ConnectMode.scan
                ? ScannerPane(controller: c)
                : ManualPane(controller: c),
          ),
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDurations.fast,
      switchInCurve: AppCurves.out,
      switchOutCurve: AppCurves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}
