import 'package:get/get.dart';

import '../../core/debug/seed_tickets.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/socket_service.dart';
import '../tasks/tasks_controller.dart';

/// Tickets with the real captured replies and injected events, no server.
/// Debug builds only (see "Before release" in CLAUDE.md).
class DebugTicketsController extends GetxController {
  DebugTicketsController({required this.tickets});

  final TicketRepository tickets;

  final isSample = SeedTickets.isActive.obs;
  final isLoading = false.obs;
  final nextFailure = RxnString();
  final requestIds = <String>[].obs;

  Future<void> toggleSample(bool value) async {
    isLoading.value = true;
    try {
      if (value) {
        await SeedTickets.start();
      } else {
        SeedTickets.stop();
      }
      isSample.value = value;
      nextFailure.value = null;
      requestIds.clear();
      tickets.scheduleRefresh();
    } finally {
      isLoading.value = false;
    }
  }

  void openTickets() =>
      Get.toNamed(AppRoutes.tasks, arguments: TasksController.showTickets);

  void openTicket(int id) => Get.toNamed(AppRoutes.ticketOf(id));

  bool _needsSample() {
    if (isSample.value) return false;
    AppNotices.info('Turn on the sample data first.');
    return true;
  }

  /// A ticket is raised to me and the server pushes `ticket_assigned`.
  void injectAssigned() {
    if (_needsSample()) return;
    final id = SeedTickets.addAssignedToMe();
    tickets.onEvent({
      'type': 'sd_event',
      'event': 'ticket_assigned',
      'data': {
        'id': id,
        'tstruct': 'help_ticket',
        'action': 'Raised',
        'by': 'rhea',
      },
    });
  }

  /// A ticket I raised that waits for approval.
  void addWaiting() {
    if (_needsSample()) return;
    SeedTickets.addAwaitingApproval();
    tickets.onEvent({'type': 'sd_event', 'event': 'submissions_changed'});
  }

  void failNext(String code, String message) {
    if (_needsSample()) return;
    SeedTickets.nextError = SocketCallError(code, message);
    SeedTickets.isLosingNextAnswer = false;
    nextFailure.value = code;
    AppNotices.info('The next update fails with $code.');
  }

  /// The next update is applied but its answer never arrives; Retry sends the
  /// same request id and gets the first result.
  void loseNextAnswer() {
    if (_needsSample()) return;
    SeedTickets.nextError = null;
    SeedTickets.isLosingNextAnswer = true;
    nextFailure.value = 'lost answer';
    AppNotices.info('The next update is done, but its answer is lost.');
  }

  void clearFailure() {
    SeedTickets.nextError = null;
    SeedTickets.isLosingNextAnswer = false;
    nextFailure.value = null;
  }

  /// The request ids the sample server has seen: a retry shows the same one.
  void showRequestIds() => requestIds.assignAll(SeedTickets.requestIds);
}
