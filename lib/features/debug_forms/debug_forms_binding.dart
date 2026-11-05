import 'package:get/get.dart';

import '../../data/db/app_database.dart';
import '../../data/form_logic/form_logic_service.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import 'debug_forms_controller.dart';

class DebugFormsBinding extends Bindings {
  @override
  void dependencies() {
    final socket = Get.find<SocketService>();
    final logic = Get.find<FormLogicService>();
    Get.lazyPut(
      () => DebugFormsController(
        session: Get.find<SessionStore>(),
        socket: socket,
        logic: logic,
        options: Get.find<FormOptionsRepository>(),
        db: Get.find<AppDatabase>(),
        conversations: Get.find<ConversationRepository>(),
        messages: Get.find<MessageRepository>(),
        samples: SampleForms(socket, Get.find<FormOptionsRepository>(), logic),
      ),
    );
  }
}
