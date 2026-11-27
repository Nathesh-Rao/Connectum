import 'package:get/get.dart';

import 'package:connectum/data/db/db.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/form_logic/form_logic_service.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/session_store.dart';
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
