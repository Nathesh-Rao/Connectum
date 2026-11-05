import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/deep_link_service.dart';
import '../../core/utils/connect_code.dart';

/// The "Have an invite code or link?" sheet of the welcome and sign-in
/// screens. The person types or pastes the text; the app never reads the
/// clipboard itself.
class InviteCodeController extends GetxController {
  InviteCodeController({required this.links});

  final DeepLinkService links;

  final input = TextEditingController();
  final error = RxnString();

  void submit() {
    final target = ConnectLinkParser.parse(input.text).value;
    if (target == null) {
      error.value =
          "That isn't a Connectum invite. Check the code or link and try again.";
      return;
    }
    links.receiveCode(target);
    Get.back<void>();
  }

  @override
  void onClose() {
    input.dispose();
    super.onClose();
  }
}
