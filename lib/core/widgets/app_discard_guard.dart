import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'app_confirm_dialog.dart';

/// Asks "Discard your changes?" before a back gesture, the back button or a
/// close leaves a screen whose draft differs from what is saved. [close]
/// leaves without asking (after a save).
class AppDiscardGuard extends StatefulWidget {
  const AppDiscardGuard({
    super.key,
    required this.isDirty,
    required this.title,
    required this.message,
    required this.discardLabel,
    required this.keepLabel,
    required this.child,
  });

  final RxBool isDirty;
  final String title;
  final String message;
  final String discardLabel;
  final String keepLabel;
  final Widget child;

  /// Asks when [isDirty] says so; true when the screen may close.
  static Future<bool> confirmLeave(
    BuildContext context, {
    required bool isDirty,
    required String title,
    required String message,
    required String discardLabel,
    required String keepLabel,
  }) async {
    if (!isDirty) return true;
    return AppConfirmDialog.ask(
      context,
      title: title,
      message: message,
      confirmLabel: discardLabel,
      cancelLabel: keepLabel,
      isDanger: true,
    );
  }

  @override
  State<AppDiscardGuard> createState() => _AppDiscardGuardState();
}

class _AppDiscardGuardState extends State<AppDiscardGuard> {
  bool _isLeaving = false;

  Future<void> _onPop(bool didPop) async {
    if (didPop) return;
    final ok = await AppDiscardGuard.confirmLeave(
      context,
      isDirty: widget.isDirty.value,
      title: widget.title,
      message: widget.message,
      discardLabel: widget.discardLabel,
      keepLabel: widget.keepLabel,
    );
    if (!ok || !mounted) return;
    setState(() => _isLeaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => Get.back<void>());
  }

  @override
  Widget build(BuildContext context) => Obx(
    () => PopScope(
      canPop: !widget.isDirty.value || _isLeaving,
      onPopInvokedWithResult: (didPop, _) => _onPop(didPop),
      child: widget.child,
    ),
  );
}
