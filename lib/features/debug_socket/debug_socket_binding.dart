import 'package:get/get.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'debug_socket_controller.dart';

class DebugSocketBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugSocketController(
        socket: Get.find<SocketService>(),
        connectivity: Get.find<ConnectivityService>(),
        session: Get.find<SessionRepository>(),
        messages: Get.find<MessageRepository>(),
        submissions: Get.find<SubmissionRepository>(),
        db: Get.find<AppDatabase>(),
      ),
    );
  }
}
