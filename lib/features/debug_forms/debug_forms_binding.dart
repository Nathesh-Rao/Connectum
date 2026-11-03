import 'package:get/get.dart';

import '../../data/form_logic/form_logic_service.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/repositories/form_options_repository.dart';
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
        samples: SampleForms(socket, Get.find<FormOptionsRepository>(), logic),
      ),
    );
  }
}
