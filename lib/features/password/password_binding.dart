import 'package:get/get.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/session_store.dart';
import 'password_controller.dart';

class PasswordBinding extends Bindings {
  PasswordBinding({this.tag});

  /// One tag per opened sheet, so a sheet opened again while the last one is
  /// closing does not share its controller.
  final String? tag;

  @override
  void dependencies() {
    Get.lazyPut(
      () => PasswordController(
        auth: Get.find<AuthRepository>(),
        store: Get.find<SessionStore>(),
      ),
      tag: tag,
    );
  }
}
