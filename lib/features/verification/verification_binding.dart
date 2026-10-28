import 'package:get/get.dart';

import '../../data/models/auth_flow.dart';
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
        flow: AuthFlow.values.firstWhere(
          (f) => f.name == args['flow'],
          orElse: () => AuthFlow.login,
        ),
        startBody: (args['body'] as Map?)?.cast<String, dynamic>(),
        retryAfter: (args['retryAfter'] as int?) ?? 30,
      ),
    );
  }
}
