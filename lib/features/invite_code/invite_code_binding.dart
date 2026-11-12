import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import 'invite_code_controller.dart';

class InviteCodeBinding extends Bindings {
  InviteCodeBinding({this.tag});

  /// One tag per opened sheet: a sheet opened again while the previous one is
  /// still closing must not share its controller.
  final String? tag;

  @override
  void dependencies() {
    Get.lazyPut(
      () => InviteCodeController(links: Get.find<DeepLinkService>()),
      tag: tag,
    );
  }
}
