import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/utils/link_open_policy.dart';
import 'link_browser_controller.dart';
import 'models/link_browser_args.dart';

class LinkBrowserBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(
      LinkBrowserController(
        args: Get.arguments as LinkBrowserArgs,
        trustedHosts: LinkHosts.trusted,
        cleartextHosts: LinkHosts.cleartext,
        web: WebViewController(),
      ),
    );
  }
}
