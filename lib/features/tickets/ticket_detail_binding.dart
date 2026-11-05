import 'package:get/get.dart';

import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/connectivity_service.dart';
import 'ticket_detail_controller.dart';

/// One controller per ticket id (its tag), so a second ticket opened from
/// another route never shares this one.
class TicketDetailBinding extends Bindings {
  @override
  void dependencies() {
    final id = int.tryParse(Get.parameters['id'] ?? '') ?? 0;
    Get.put(
      TicketDetailController(
        ticketId: id,
        tickets: Get.find<TicketRepository>(),
        people: Get.find<GroupRepository>(),
        files: Get.find<FormFileRepository>(),
        connectivity: Get.find<ConnectivityService>(),
      ),
      tag: '$id',
    );
  }
}
