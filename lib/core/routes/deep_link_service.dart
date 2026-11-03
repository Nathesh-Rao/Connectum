import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';

import '../../data/session_store.dart';
import '../utils/connect_code.dart';
import 'app_routes.dart';

class AppLink {
  const AppLink({required this.code, this.branch, required this.host});

  final String code;
  final String? branch;
  final String host;
}

/// `/connect/<CODE>` links are kept as a pending link and never consumed yet:
/// what the code identifies for joining is not confirmed (see CLAUDE.md).
/// A link only brings the user to the enterprises screen.
class DeepLinkService extends GetxService {
  DeepLinkService(this._appLinks, this._store);

  final AppLinks _appLinks;
  final SessionStore _store;
  StreamSubscription<Uri>? _subscription;

  AppLink? pendingLink;
  bool _hasOpened = false;

  bool get isLoggedIn => _store.isSignedIn;

  @override
  Future<void> onInit() async {
    super.onInit();
    _subscription = _appLinks.uriLinkStream.listen(handle);
    final initial = await _appLinks.getInitialLink();
    if (initial != null) handle(initial);
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }

  void handle(Uri uri) {
    final link = map(uri);
    if (link == null) return;
    pendingLink = link;
    _hasOpened = false;
    if (isLoggedIn) openPending();
  }

  /// Opens the enterprises screen for a pending link, once per link.
  void openPending() {
    if (pendingLink == null || _hasOpened || !isLoggedIn) return;
    _hasOpened = true;
    if (Get.currentRoute != AppRoutes.enterprises) {
      Get.toNamed(AppRoutes.enterprises);
    }
  }

  AppLink? map(Uri uri) {
    final parsed = ConnectLinkParser.parse(uri.toString()).value;
    if (parsed == null) return null;
    return AppLink(code: parsed.code, branch: parsed.branch, host: uri.host);
  }
}
