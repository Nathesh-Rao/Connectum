import 'package:get/get.dart';

import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/inbox_field_kinds.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/inbox_views_repository.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../home_shell/home_shell_controller.dart';
import '../tickets/ticket_detail_controller.dart';
import 'inbox_approvals_controller.dart';
import 'inbox_controller.dart';
import 'inbox_views_controller.dart';

class InboxBinding extends Bindings {
  @override
  void dependencies() {
    final tickets = Get.find<TicketRepository>();
    final files = Get.find<FormFileRepository>();
    final connectivity = Get.find<ConnectivityService>();
    final inbox = Get.find<InboxRepository>();
    Get.put(
      InboxController(
        inbox: inbox,
        approvals: InboxApprovals(
          approvals: Get.find<ApprovalRepository>(),
          inbox: inbox,
          connectivity: connectivity,
        ),
        views: InboxViews(
          repo: Get.find<InboxViewsRepository>(),
          connectivity: connectivity,
        ),
        tickets: tickets,
        store: Get.find<SessionStore>(),
        connectivity: connectivity,
        shell: Get.find<HomeShellController>(),
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
