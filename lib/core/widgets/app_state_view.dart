import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_button.dart';
import 'app_loading.dart';
import 'app_state_image.dart';

enum AppViewState { content, loading, empty, error, offline, noResults, locked }

class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.state,
    required this.child,
    this.emptyImage = AppStateImageKind.emptyGeneric,
    this.image,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.errorMessage = 'Something went wrong.',
    this.onRetry,
    this.loadingChild,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  final AppViewState state;
  final Widget child;
  final AppStateImageKind emptyImage;

  /// Replaces the picture of any variant.
  final AppStateImageKind? image;
  final String emptyTitle;
  final String? emptyMessage;
  final String errorMessage;
  final VoidCallback? onRetry;

  /// Shown instead of the placeholder while loading (skeleton rows).
  final Widget? loadingChild;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AppViewState.content => child,
      AppViewState.loading => loadingChild ?? const _Message(),
      AppViewState.empty => _Message(
        image: image ?? emptyImage,
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      ),
      AppViewState.error => _Message(
        image: image ?? AppStateImageKind.error,
        title: 'Could not load',
        message: errorMessage,
        onRetry: onRetry,
      ),
      AppViewState.offline => _Message(
        image: image ?? AppStateImageKind.offline,
        title: 'You are offline',
        message: 'Check your connection and try again.',
        onRetry: onRetry,
      ),
      AppViewState.noResults => _Message(
        image: image ?? AppStateImageKind.noResults,
        title: emptyTitle,
        message: emptyMessage,
      ),
      AppViewState.locked => _Message(
        image: image ?? AppStateImageKind.locked,
        title: emptyTitle,
        message: emptyMessage,
      ),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    this.image,
    this.title,
    this.message,
    this.onRetry,
    this.actionLabel,
    this.onAction,
  });

  final AppStateImageKind? image;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null)
              AppStateImage(kind: image!)
            else
              const AppLoading.large(),
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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 200,
                child: AppButton.primary(
                  label: actionLabel!,
                  isCompact: true,
                  onPressed: onAction,
                ),
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
