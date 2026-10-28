import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';

import 'app_routes.dart';

class AppLink {
  const AppLink({required this.route, this.arguments});

  final String route;
  final Map<String, String>? arguments;
}

class DeepLinkService extends GetxService {
  DeepLinkService(this._appLinks);

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;

  AppLink? pendingLink;

  // Stub until the session exists.
  bool get isLoggedIn => false;

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
    if (isLoggedIn) {
      open(link);
    } else {
      pendingLink = link;
    }
  }

  void openPending() {
    final link = pendingLink;
    if (link == null || !isLoggedIn) return;
    pendingLink = null;
    open(link);
  }

  void open(AppLink link) => Get.toNamed(link.route, arguments: link.arguments);

  // https://<host>/connect/<CODE>[?branch=<Name>] and connectum:<CODE>[?branch=<Name>]
  AppLink? map(Uri uri) {
    final rawCode = uri.scheme == 'connectum'
        ? uri.path
        : (uri.pathSegments.length == 2 && uri.pathSegments.first == 'connect'
              ? uri.pathSegments[1]
              : '');
    final code = rawCode.replaceAll(RegExp(r'[-\s]'), '').toUpperCase();
    if (code.isEmpty) return null;
    final branch = uri.queryParameters['branch'];
    return AppLink(
      route: AppRoutes.enterprises,
      arguments: {'code': code, 'branch': ?branch},
    );
  }
}
