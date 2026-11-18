import 'package:get/get.dart';

import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/smart_view/sv_prefs.dart';
import '../../data/socket/connectivity_service.dart';
import '../smart_view/smart_view_controller.dart';
import '../tickets/ticket_detail_controller.dart';
import 'debug_smart_views_controller.dart';

class DebugSmartViewsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => DebugSmartViewsController.create(
        (views) => SmartViewController(
          repo: Get.find<SmartViewRepository>(),
          tickets: Get.find<TicketRepository>(),
          submissions: Get.find<SubmissionRepository>(),
          prefs: SmartViewPrefs(),
          views: views,
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
