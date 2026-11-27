import 'package:get/get.dart';

import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/tickets/tickets.dart';
import '../../data/session_store.dart';
import '../home_shell/home_shell_controller.dart';
import 'inbox_approvals_controller.dart';
import 'inbox_controller.dart';
import 'inbox_tour.dart';
import 'inbox_views_controller.dart';

class InboxBinding extends Bindings {
  @override
  void dependencies() {
    final tickets = Get.find<TicketRepository>();
    final files = Get.find<FormFileRepository>();
    final connectivity = Get.find<ConnectivityService>();
    final inbox = Get.find<InboxRepository>();
    final store = Get.find<SessionStore>();
    Get.put(
      InboxController(
        inbox: inbox,
        approvals: InboxApprovals(
          approvals: Get.find<ApprovalRepository>(),
          inbox: inbox,
          connectivity: connectivity,
          me: (store.userId ?? '').toLowerCase(),
        ),
        views: InboxViews(
          repo: Get.find<InboxViewsRepository>(),
          connectivity: connectivity,
        ),
        files: Get.find<SvFileRepository>(),
        liveEvents: Get.find<SocketService>().events,
        liveOnline: Get.find<SocketService>().onOnline,
        tickets: tickets,
        store: store,
        connectivity: connectivity,
        shell: Get.find<HomeShellController>(),
        tour: Get.isRegistered<TourService>()
            ? InboxTour(service: Get.find<TourService>())
            : null,
        fieldKinds: InboxFieldKinds(Get.find<SmartViewRepository>()),
        newTicketDetail: (id) => TicketDetailController(
          ticketId: id,
          tickets: tickets,
          files: files,
          connectivity: connectivity,
        ),
      ),
    );
  }
}
