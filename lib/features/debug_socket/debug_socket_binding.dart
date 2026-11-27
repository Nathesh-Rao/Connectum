import 'package:get/get.dart';

import 'package:connectum/data/db/db.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
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
        conversationRepository: Get.find<ConversationRepository>(),
        submissions: Get.find<SubmissionRepository>(),
        presence: Get.find<PresenceRepository>(),
        auth: Get.find<AuthRepository>(),
        db: Get.find<AppDatabase>(),
      ),
    );
  }
}
