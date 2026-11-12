import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/message.dart';

/// The mark at the bottom right of my own bubble: a clock while waiting, a
/// tick when sent, two ticks when delivered, two accent ticks when read (direct
/// messages only; groups and the global room stop at the single tick) and an
/// error mark when it failed. A change fades and scales in place.
class MessageStatusMark extends StatelessWidget {
  const MessageStatusMark({
    super.key,
    required this.status,
    required this.isDirect,
  });

  final MessageStatus status;
  final bool isDirect;

  @override
  Widget build(BuildContext context) {
    final effective = isDirect
        ? status
        : (status == MessageStatus.delivered || status == MessageStatus.read)
        ? MessageStatus.sent
        : status;
    final (icon, color, label) = switch (effective) {
      MessageStatus.pending ||
      MessageStatus.sending => (Icons.schedule, AppColors.muted, 'Sending'),
      MessageStatus.sent => (Icons.check, AppColors.muted, 'Sent'),
      MessageStatus.delivered => (Icons.done_all, AppColors.muted, 'Delivered'),
      MessageStatus.read => (Icons.done_all, AppColors.primaryBright, 'Read'),
      MessageStatus.failed => (
        Icons.error_outline,
        AppColors.error,
        'Not sent',
      ),
    };
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: AnimatedSwitcher(
        duration: reduced ? Duration.zero : AppDurations.base,
        switchInCurve: AppCurves.out,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          icon,
          key: ValueKey(
            icon.codePoint * 10 + (color == AppColors.primaryBright ? 1 : 0),
          ),
          size: AppSpacing.statusIcon,
          color: color,
        ),
      ),
    );
  }
}
