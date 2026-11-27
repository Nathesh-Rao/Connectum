import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'package:connectum/features/tickets/tickets.dart';
import '../../data/smart_view/sv_prefs.dart';
import 'debug_smart_query_controller.dart';

class DebugSmartQueryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugSmartQueryController(
        view: SmartViewController(
          repo: Get.find<SmartViewRepository>(),
          tickets: Get.find<TicketRepository>(),
          submissions: Get.find<SubmissionRepository>(),
          prefs: SmartViewPrefs(),
          newTicketDetail: (id) => TicketDetailController(
            ticketId: id,
            tickets: Get.find<TicketRepository>(),
            files: Get.find<FormFileRepository>(),
            connectivity: Get.find<ConnectivityService>(),
          ),
        ),
      ),
    );
  }
}
