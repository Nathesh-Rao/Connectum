import 'package:get/get.dart';

import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/inbox_field_kinds.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/sv_file_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/connectivity_service.dart';
import 'ticket_detail_controller.dart';

/// One controller per ticket id (its tag), so a second ticket opened from
/// another route never shares this one.
class TicketDetailBinding extends Bindings {
  @override
  void dependencies() {
    final smartView = _maybe<SmartViewRepository>();
    final id = int.tryParse(Get.parameters['id'] ?? '') ?? 0;
    Get.put(
      TicketDetailController(
        ticketId: id,
        tickets: Get.find<TicketRepository>(),
        files: Get.find<FormFileRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        inbox: _maybe<InboxRepository>(),
        approvals: _maybe<ApprovalRepository>(),
        fieldKinds: smartView == null ? null : InboxFieldKinds(smartView),
        svFiles: _maybe<SvFileRepository>(),
      ),
      tag: '$id',
    );
  }

  /// The extras of the record screen are optional: without one the screen
  /// shows what `submission.get` gave.
  static T? _maybe<T>() => Get.isRegistered<T>() ? Get.find<T>() : null;
}
