import 'package:get/get.dart';

import '../../data/form_logic/form_logic_service.dart';
import '../../data/form_logic/sample_forms.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/session_store.dart';
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
