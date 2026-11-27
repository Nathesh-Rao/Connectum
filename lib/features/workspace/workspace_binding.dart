import 'package:get/get.dart';

import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/commands/commands.dart';
import 'package:connectum/features/home_shell/home_shell.dart';
import 'package:connectum/features/tickets/tickets.dart';
import '../../data/session_store.dart';
import 'workspace_tour.dart';
import 'workspace_controller.dart';

class WorkspaceBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() {
      final tours = Get.isRegistered<TourService>()
          ? Get.find<TourService>()
          : null;
      late final WorkspaceController controller;
      return controller = WorkspaceController(
        submissions: Get.find<SubmissionRepository>(),
        store: Get.find<SessionStore>(),
        connectivity: Get.find<ConnectivityService>(),
        formOptions: Get.find<FormOptionsRepository>(),
        shell: Get.isRegistered<HomeShellController>()
            ? Get.find<HomeShellController>()
            : null,
        commands: Get.find<CommandRepository>(),
        messages: Get.find<MessageRepository>(),
        marks: Get.find<MarksRepository>(),
        workspace: Get.find<WorkspaceRepository>(),
        tickets: Get.find<TicketRepository>(),
        smartView: Get.find<SmartViewRepository>(),
        newTicketDetail: (id) => TicketDetailController(
          ticketId: id,
          tickets: Get.find<TicketRepository>(),
          files: Get.find<FormFileRepository>(),
          connectivity: Get.find<ConnectivityService>(),
        ),
        tour: tours == null ? null : WorkspaceTour(service: tours),
        commandsTour: tours == null
            ? null
            : CommandsTour(
                service: tours,
                isListOpen: () => controller.prompt.isNameList,
                hasRows: () => controller.prompt.hasRows,
              ),
      );
    });
  }
}
