import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_animation_placeholder.dart';
import 'app_button.dart';

enum AppViewState { content, loading, empty, error, offline }

class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.state,
    required this.child,
    this.emptyAnimation = 'empty',
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.errorMessage = 'Something went wrong.',
    this.onRetry,
  });

  final AppViewState state;
  final Widget child;
  final String emptyAnimation;
  final String emptyTitle;
  final String? emptyMessage;
  final String errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AppViewState.content => child,
      AppViewState.loading => const _Message(animation: 'loading'),
      AppViewState.empty => _Message(
        animation: emptyAnimation,
        title: emptyTitle,
        message: emptyMessage,
      ),
      AppViewState.error => _Message(
        animation: 'error',
        title: 'Could not load',
        message: errorMessage,
        onRetry: onRetry,
      ),
      AppViewState.offline => _Message(
        animation: 'offline',
        title: 'You are offline',
        message: 'Check your connection and try again.',
        onRetry: onRetry,
      ),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.animation,
    this.title,
    this.message,
    this.onRetry,
  });

  final String animation;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAnimationPlaceholder(name: animation),
            if (title != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                title!,
                style: AppText.subtitle,
                textAlign: TextAlign.center,
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: AppText.readable,
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 160,
                child: AppButton.secondary(label: 'Retry', onPressed: onRetry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
