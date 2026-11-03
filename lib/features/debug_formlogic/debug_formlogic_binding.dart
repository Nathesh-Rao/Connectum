import 'package:get/get.dart';

import '../../data/form_logic/form_logic_service.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';
import 'debug_formlogic_controller.dart';

class DebugFormLogicBinding extends Bindings {
  @override
  void dependencies() {
    final socket = Get.find<SocketService>();
    Get.lazyPut(
      () => DebugFormLogicController(
        session: Get.find<SessionStore>(),
        socket: socket,
        samples: SampleForms(
          socket,
          Get.find<FormOptionsRepository>(),
          Get.find<FormLogicService>(),
        ),
      ),
    );
  }
}
