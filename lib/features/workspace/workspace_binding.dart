import 'package:get/get.dart';

import '../../data/repositories/command_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/repositories/workspace_repository.dart';
import '../tickets/ticket_detail_controller.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../home_shell/home_shell_controller.dart';
import 'workspace_controller.dart';

class WorkspaceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => WorkspaceController(
        submissions: Get.find<SubmissionRepository>(),
        store: Get.find<SessionStore>(),
        connectivity: Get.find<ConnectivityService>(),
        formOptions: Get.find<FormOptionsRepository>(),
        shell: Get.isRegistered<HomeShellController>()
            ? Get.find<HomeShellController>()
            : null,
        commands: Get.find<CommandRepository>(),
        messages: Get.find<MessageRepository>(),
        workspace: Get.find<WorkspaceRepository>(),
        tickets: Get.find<TicketRepository>(),
        smartView: Get.find<SmartViewRepository>(),
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
