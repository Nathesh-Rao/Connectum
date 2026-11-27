import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'models/link_browser_args.dart';

enum LinkBrowserError { offline, ssl, http, other }

/// The in-app page of a trusted link: loading, errors and the menu. The web
/// view is JavaScript-enabled but has no channel to the app, and any
/// navigation that leaves the trusted hosts goes to the phone's browser.
class LinkBrowserController extends GetxController {
  LinkBrowserController({
    required this.args,
    required this.trustedHosts,
    this.cleartextHosts = const {},
    this.launcher = const LinkLauncher(),
    this.web,
  });

  final LinkBrowserArgs args;
  final Set<String> trustedHosts;
  final Set<String> cleartextHosts;
  final LinkLauncher launcher;

  /// Null in tests that don't need a real page.
  final WebViewController? web;

  final progress = 0.obs;
  final title = ''.obs;
  final currentUrl = ''.obs;
  final isLoading = true.obs;
  final hasContent = false.obs;
  final canGoBack = false.obs;
  final error = Rxn<LinkBrowserError>();
  final notice = RxnString();
  Timer? _noticeTimer;

  String get host =>
      LinkOpenPolicy.normalizeHost(Uri.tryParse(currentUrl.value)?.host ?? '');

  bool get isSecure => Uri.tryParse(currentUrl.value)?.scheme == 'https';

  String get shownTitle => title.value.isNotEmpty
      ? title.value
      : (args.title.isNotEmpty ? args.title : host);

  static String errorMessage(LinkBrowserError e) => switch (e) {
    LinkBrowserError.offline =>
      "Can't reach this page. Check your connection and try again.",
    LinkBrowserError.ssl =>
      "This page's security certificate can't be trusted, so it wasn't opened.",
    LinkBrowserError.http => 'The page answered with an error.',
    LinkBrowserError.other => "This page couldn't be loaded.",
  };

  @override
  void onInit() {
    super.onInit();
    currentUrl.value = args.url;
    final w = web;
    if (w == null) return;
    fireAndLog('link_browser_controller', () => _start(w));
  }

  Future<void> _start(WebViewController w) async {
    await w.setJavaScriptMode(JavaScriptMode.unrestricted);
    await w.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: handleNavigation,
        onPageStarted: handlePageStarted,
        onProgress: handleProgress,
        onPageFinished: handlePageFinished,
        onWebResourceError: handleError,
        onHttpError: (e) => handleHttpError(e.response?.statusCode),
        onUrlChange: (c) {
          final url = c.url;
          if (url != null) currentUrl.value = url;
          fireAndLog('link_browser_controller', () => _syncBack());
        },
      ),
    );
    final uri = Uri.tryParse(args.url);
    if (uri == null) {
      error.value = LinkBrowserError.other;
      isLoading.value = false;
      return;
    }
    await w.loadRequest(uri);
  }

  Future<NavigationDecision> handleNavigation(NavigationRequest req) async {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;
    if (req.url == 'about:blank') return NavigationDecision.navigate;
    if (!req.isMainFrame) {
      final isWeb = uri.scheme == 'https' || uri.scheme == 'http';
      return isWeb ? NavigationDecision.navigate : NavigationDecision.prevent;
    }
    final mode = LinkOpenPolicy.decide(
      req.url,
      trustedHosts,
      cleartextHosts: cleartextHosts,
    );
    switch (mode) {
      case LinkOpenMode.inApp:
        return NavigationDecision.navigate;
      case LinkOpenMode.external:
        final isOpened = await launcher.openExternal(req.url);
        if (!isOpened) _say("Couldn't open that link.");
        return NavigationDecision.prevent;
      case LinkOpenMode.blocked:
        _say(LinkOpenPolicy.blockedMessage);
        return NavigationDecision.prevent;
    }
  }

  void handlePageStarted(String url) {
    currentUrl.value = url;
    error.value = null;
    isLoading.value = true;
    progress.value = 0;
  }

  void handleProgress(int value) {
    progress.value = value;
    if (value >= 40 && error.value == null) hasContent.value = true;
  }

  Future<void> handlePageFinished(String url) async {
    currentUrl.value = url;
    isLoading.value = false;
    progress.value = 100;
    if (error.value == null) hasContent.value = true;
    final w = web;
    if (w != null) title.value = (await w.getTitle()) ?? '';
    await _syncBack();
  }

  void handleError(WebResourceError e) {
    if (e.isForMainFrame == false) return;
    error.value = switch (e.errorType) {
      WebResourceErrorType.hostLookup ||
      WebResourceErrorType.connect ||
      WebResourceErrorType.io ||
      WebResourceErrorType.timeout => LinkBrowserError.offline,
      WebResourceErrorType.failedSslHandshake => LinkBrowserError.ssl,
      _ => LinkBrowserError.other,
    };
    isLoading.value = false;
  }

  void handleHttpError(int? status) {
    if (status == null || status < 400) return;
    error.value = LinkBrowserError.http;
    isLoading.value = false;
  }

  Future<void> _syncBack() async {
    final w = web;
    if (w != null) canGoBack.value = await w.canGoBack();
  }

  /// Back inside the page first, then closes.
  Future<void> goBackOrClose() async {
    final w = web;
    if (w != null && await w.canGoBack()) {
      await w.goBack();
      return;
    }
    Get.back<void>();
  }

  Future<void> reload() async {
    error.value = null;
    isLoading.value = true;
    final w = web;
    if (w == null) return;
    if (hasContent.value) {
      await w.reload();
    } else {
      final uri = Uri.tryParse(currentUrl.value);
      if (uri != null) await w.loadRequest(uri);
    }
  }

  Future<void> openInBrowser() async {
    final isOpened = await launcher.openExternal(currentUrl.value);
    if (!isOpened) _say("Couldn't open the browser.");
  }

  Future<void> copyLink() async {
    await Clipboard.setData(ClipboardData(text: currentUrl.value));
    _say('Link copied');
  }

  Future<void> shareLink() async {
    try {
      await SharePlus.instance.share(ShareParams(text: currentUrl.value));
    } on PlatformException {
      _say("Couldn't share the link.");
    }
  }

  void _say(String text) {
    notice.value = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(
      AppDurations.copiedHold * 2,
      () => notice.value = null,
    );
  }

  @override
  void onClose() {
    _noticeTimer?.cancel();
    super.onClose();
  }
}
