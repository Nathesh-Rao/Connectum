import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'link_browser_controller.dart';

enum _MenuItem { reload, browser, copy, share }

/// A full-screen in-app page: close, title and host, a thin progress line and
/// a menu, over the web view.
class LinkBrowserView extends GetView<LinkBrowserController> {
  const LinkBrowserView({super.key, this.pageBuilder = _webPage});

  /// Builds the page area; tests replace it so no real web view is needed.
  final Widget Function(WebViewController? web) pageBuilder;

  static Widget _webPage(WebViewController? web) =>
      web == null ? const SizedBox.shrink() : WebViewWidget(controller: web);

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => PopScope(
        canPop: !c.canGoBack.value,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) c.goBackOrClose();
        },
        child: Scaffold(
          backgroundColor: AppColors.white,
          body: SafeArea(
            child: Column(
              children: [
                _Bar(controller: c),
                _Progress(controller: c),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: pageBuilder(c.web)),
                      Positioned.fill(child: _Cover(controller: c)),
                      Positioned(
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                        child: Obx(
                          () => c.notice.value == null
                              ? const SizedBox.shrink()
                              : _Notice(text: c.notice.value!),
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
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.controller});

  final LinkBrowserController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final c = controller;
    if (c.error.value != null) return _ErrorPanel(controller: c);
    if (c.hasContent.value) return const SizedBox.shrink();
    return const ColoredBox(
      color: AppColors.white,
      child: AppStateView(
        state: AppViewState.loading,
        child: SizedBox.shrink(),
      ),
    );
  });
}

class _Bar extends StatelessWidget {
  const _Bar({required this.controller});

  final LinkBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          AppButton.icon(
            icon: Icons.close,
            onPressed: Get.back<void>,
            semanticLabel: 'Close',
          ),
          Expanded(
            child: Obx(
              () => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.shownTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: AppText.sizeSubtitle - 2,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: AppColors.ink,
                    ),
                  ),
                  Row(
                    children: [
                      if (c.isSecure) ...[
                        const Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                      ],
                      Flexible(
                        child: Text(
                          c.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppText.fontFamily,
                            fontSize: AppText.sizeCaption,
                            height: 1.2,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<_MenuItem>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, color: AppColors.muted),
            color: AppColors.white,
            onSelected: (item) => switch (item) {
              _MenuItem.reload => c.reload(),
              _MenuItem.browser => c.openInBrowser(),
              _MenuItem.copy => c.copyLink(),
              _MenuItem.share => c.shareLink(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: _MenuItem.reload, child: Text('Reload')),
              PopupMenuItem(
                value: _MenuItem.browser,
                child: Text('Open in browser'),
              ),
              PopupMenuItem(value: _MenuItem.copy, child: Text('Copy link')),
              PopupMenuItem(value: _MenuItem.share, child: Text('Share')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});

  final LinkBrowserController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final c = controller;
    final isShown = c.isLoading.value && c.error.value == null;
    return SizedBox(
      height: 2,
      child: isShown
          ? LinearProgressIndicator(
              value: c.progress.value == 0 ? null : c.progress.value / 100,
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.line,
            )
          : const ColoredBox(color: AppColors.line),
    );
  });
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.controller});

  final LinkBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final e = c.error.value!;
    return ColoredBox(
      color: AppColors.white,
      child: Column(
        children: [
          Expanded(
            child: AppStateView(
              state: e == LinkBrowserError.offline
                  ? AppViewState.offline
                  : AppViewState.error,
              errorMessage: LinkBrowserController.errorMessage(e),
              onRetry: c.reload,
              child: const SizedBox.shrink(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppButton.text(
              label: 'Open in browser',
              tone: AppTextButtonTone.accent,
              onPressed: c.openInBrowser,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.mdAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: AppText.sizeReadable,
            color: AppColors.white,
          ),
        ),
      ),
    ),
  );
}
