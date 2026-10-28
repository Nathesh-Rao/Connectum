import 'package:get/get.dart';

import '../../data/repositories/auth_repository.dart';
import 'verification_controller.dart';

class VerificationBinding extends Bindings {
  @override
  void dependencies() {
    final args = (Get.arguments as Map?) ?? {};
    Get.lazyPut(
      () => VerificationController(
        auth: Get.find<AuthRepository>(),
        email: '${args['email'] ?? ''}',
        isRegister: args['isRegister'] == true,
        registerBody: (args['registerBody'] as Map?)?.cast<String, dynamic>(),
        retryAfter: (args['retryAfter'] as int?) ?? 30,
      ),
    );
  }
}
