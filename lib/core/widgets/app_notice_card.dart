import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_highlight_text.dart';

enum AppNoticeVariant {
  info(Icons.info_outline, AppColors.muted),
  success(Icons.check_circle_outline, AppColors.yesDot),
  warning(Icons.warning_amber_rounded, AppColors.accent),
  error(Icons.error_outline, AppColors.error);

  const AppNoticeVariant(this.icon, this.color);

  final IconData icon;
  final Color color;
}

/// A floating, dismissible notice. Place it in a [Stack] above the content
/// (never in the layout flow) so it overlays without pushing anything. It
/// slides and fades in, leaves on its own after [holdFor], on a swipe or on
/// the close button (never on its own when [holdFor] is null), and calls [onDismiss] once in every case.
class AppNoticeCard extends StatefulWidget {
  const AppNoticeCard({
    super.key,
    this.title,
    required this.message,
    required this.onDismiss,
    this.values = const {},
    this.variant = AppNoticeVariant.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.holdFor = const Duration(seconds: 10),
  });

  final String? title;
  final String message;

  /// Names in [message] (`{key}` placeholders) that stand out.
  final Map<String, String> values;
  final AppNoticeVariant variant;
  final IconData? icon;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration? holdFor;

  @override
  State<AppNoticeCard> createState() => _AppNoticeCardState();
}

class _AppNoticeCardState extends State<AppNoticeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.base,
    reverseDuration: AppDurations.fast,
  );
  Timer? _timer;
  bool _isDone = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    final hold = widget.holdFor;
    if (hold != null) _timer = Timer(hold, _leave);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (_isDone) return;
    _isDone = true;
    _timer?.cancel();
    widget.onDismiss();
  }

  Future<void> _leave() async {
    if (_isDone) return;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) _finish();
  }

  @override
  Widget build(BuildContext context) {
    final isReduced = MediaQuery.disableAnimationsOf(context);
    final curved = CurvedAnimation(parent: _controller, curve: AppCurves.out);
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.title == null
          ? AppHighlightText.plain(widget.message, widget.values)
          : '${AppHighlightText.plain(widget.title!, widget.values)}. ${AppHighlightText.plain(widget.message, widget.values)}',
      child: FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              0,
              isReduced ? 0 : (1 - curved.value) * AppDistances.enter,
            ),
            child: child,
          ),
          child: Dismissible(
            key: ValueKey('app-notice-card-${widget.title}-${widget.message}'),
            onDismissed: (_) => _finish(),
            child: _Card(
              title: widget.title,
              message: widget.message,
              values: widget.values,
              variant: widget.variant,
              icon: widget.icon,
              actionLabel: widget.actionLabel,
              onAction: widget.onAction,
              onClose: _leave,
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.message,
    required this.values,
    required this.variant,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.onClose,
  });

  final String? title;
  final String message;
  final Map<String, String> values;
  final AppNoticeVariant variant;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.sm,
        top: AppSpacing.xxs,
        bottom: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.avatarSmall,
            height: AppSpacing.avatarSmall,
            decoration: const BoxDecoration(
              color: AppColors.avatarBg,
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(icon ?? variant.icon, size: 18, color: variant.color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    AppHighlightText(
                      title!,
                      values: values,
                      style: AppText.bodyStrong,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                  ],
                  AppHighlightText(
                    message,
                    values: values,
                    style: title == null
                        ? AppText.readable
                        : AppText.readable.copyWith(color: AppColors.muted),
                  ),
                  if (actionLabel != null && onAction != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onAction,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          actionLabel!,
                          style: AppText.readableStrong.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Dismiss',
            excludeSemantics: true,
            child: InkResponse(
              onTap: onClose,
              radius: AppSpacing.iconButton / 2,
              child: const SizedBox(
                width: AppSpacing.minTapTarget,
                height: AppSpacing.minTapTarget,
                child: Icon(Icons.close, size: 20, color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
