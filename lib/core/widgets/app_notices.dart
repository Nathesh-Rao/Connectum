import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_highlight_text.dart';
import 'app_notice_card.dart';

class _Notice {
  _Notice({
    required this.id,
    required this.key,
    required this.title,
    required this.message,
    required this.values,
    required this.variant,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    required this.holdFor,
    required this.onDismiss,
  });

  final int id;
  final String key;
  final String? title;
  final String message;
  final Map<String, String> values;
  final AppNoticeVariant variant;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration? holdFor;
  final VoidCallback? onDismiss;

  String get text => AppHighlightText.plain(message, values);
}

/// The one way to tell the person something short. Works from anywhere (no
/// BuildContext): [AppNoticeHost], mounted once above the navigator, draws
/// the card over every screen, sheet and dialog. One notice at a time; a new
/// one replaces the old, and the same text is not shown twice.
class AppNotices {
  AppNotices._();

  static final _current = ValueNotifier<_Notice?>(null);
  static int _nextId = 0;

  static void show(
    String message, {
    String? title,
    AppNoticeVariant variant = AppNoticeVariant.info,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    bool isPersistent = false,
    VoidCallback? onDismiss,
    String? key,
    Map<String, String> values = const {},
  }) {
    final text = AppHighlightText.plain(message, values);
    final noticeKey = key ?? text;
    final open = _current.value;
    if (open != null && open.key == noticeKey && open.text == text) {
      return;
    }
    _current.value = _Notice(
      id: _nextId++,
      key: noticeKey,
      title: title,
      message: message,
      values: values,
      variant: variant,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      holdFor: isPersistent
          ? null
          : switch (variant) {
              AppNoticeVariant.error => const Duration(seconds: 8),
              AppNoticeVariant.warning => const Duration(seconds: 6),
              _ => const Duration(seconds: 4),
            },
      onDismiss: onDismiss,
    );
  }

  static void info(String message) => show(message);

  static void success(String message) =>
      show(message, variant: AppNoticeVariant.success);

  static void warning(String message) =>
      show(message, variant: AppNoticeVariant.warning);

  static void error(String message) =>
      show(message, variant: AppNoticeVariant.error);

  /// Removes the notice with [key] (the message text by default) if it is
  /// the one showing. [onDismiss] is not called.
  static void hide(String key) {
    if (_current.value?.key == key) _current.value = null;
  }

  static void _dismiss(_Notice notice) {
    if (_current.value?.id == notice.id) _current.value = null;
    notice.onDismiss?.call();
  }
}

/// Hosts [AppNotices] above [child]: top of the screen, below the status bar,
/// above every route including sheets and dialogs.
class AppNoticeHost extends StatelessWidget {
  const AppNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + AppSpacing.sm;
    return Stack(
      children: [
        child,
        Positioned(
          top: top,
          left: AppSpacing.page,
          right: AppSpacing.page,
          child: Material(
            type: MaterialType.transparency,
            child: ValueListenableBuilder<_Notice?>(
              valueListenable: AppNotices._current,
              builder: (context, notice, _) {
                if (notice == null) return const SizedBox.shrink();
                return AppNoticeCard(
                  key: ValueKey(notice.id),
                  title: notice.title,
                  message: notice.message,
                  values: notice.values,
                  variant: notice.variant,
                  icon: notice.icon,
                  actionLabel: notice.actionLabel,
                  onAction: notice.onAction,
                  holdFor: notice.holdFor,
                  onDismiss: () => AppNotices._dismiss(notice),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
