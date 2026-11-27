import 'package:get/get.dart';

import '../../core/tour/tour_service.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/sv_file_repository.dart';
import '../../data/repositories/sv_saved_views_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/smart_view/sv_prefs.dart';
import '../tickets/ticket_detail_controller.dart';
import 'smart_view_controller.dart';
import 'smart_view_tour.dart';

/// Called by the home binding: the Smart view tab lives with the home.
class SmartViewBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(
      SmartViewController(
        repo: Get.find<SmartViewRepository>(),
        tickets: Get.find<TicketRepository>(),
        submissions: Get.find<SubmissionRepository>(),
        views: Get.isRegistered<SvSavedViewsRepository>()
            ? Get.find<SvSavedViewsRepository>()
            : null,
        files: Get.isRegistered<SvFileRepository>()
            ? Get.find<SvFileRepository>()
            : null,
        inbox: Get.isRegistered<InboxRepository>()
            ? Get.find<InboxRepository>()
            : null,
        prefs: Get.isRegistered<SmartViewPrefs>()
            ? Get.find<SmartViewPrefs>()
            : SmartViewPrefs(),
        tour: Get.isRegistered<TourService>()
            ? SmartViewTour(service: Get.find<TourService>())
            : null,
        newTicketDetail: (id) => TicketDetailController(
          ticketId: id,
          tickets: Get.find<TicketRepository>(),
          files: Get.find<FormFileRepository>(),
          connectivity: Get.find<ConnectivityService>(),
        ),
      ),
    );
  }
}
