import 'package:get/get.dart';

import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'package:connectum/features/commands/commands.dart';
import 'package:connectum/features/home_shell/home_shell.dart';
import 'package:connectum/features/tickets/tickets.dart';
import 'conversation_tour.dart';

import '../../core/routes/home_reload.dart';
import '../../data/ai/ai_repository.dart';
import '../../data/ai/ai_setup_cache.dart';
import '../../data/attachment_cache.dart';
import '../../data/session_store.dart';
import 'conversation_controller.dart';

/// Puts one controller per conversation id (its tag), so another route's
/// disposal can never delete it.
class ConversationBinding extends Bindings {
  @override
  void dependencies() {
    final id = Uri.decodeComponent(Get.parameters['id'] ?? '');
    final tours = Get.isRegistered<TourService>()
        ? Get.find<TourService>()
        : null;
    late final ConversationController controller;
    controller = Get.put(
      ConversationController(
        conversationId: id,
        messages: Get.find<MessageRepository>(),
        conversations: Get.find<ConversationRepository>(),
        presence: Get.find<PresenceRepository>(),
        profiles: Get.find<PeopleProfiles>(),
        typing: Get.find<TypingRepository>(),
        submissions: Get.find<SubmissionRepository>(),
        smartView: Get.find<SmartViewRepository>(),
        formOptions: Get.find<FormOptionsRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        shell: Get.isRegistered<HomeShellController>()
            ? Get.find<HomeShellController>()
            : null,
        socket: Get.find<SocketService>(),
        store: Get.find<SessionStore>(),
        e2e: Get.find<E2eRepository>(),
        commands: Get.find<CommandRepository>(),
        attachments: Get.find<AttachmentRepository>(),
        attachmentCache: Get.find<AttachmentCache>(),
        tickets: Get.find<TicketRepository>(),
        aiRepository: Get.find<AiRepository>(),
        aiSetup: Get.find<AiSetupCache>(),
        avatars: Get.find<PeopleAvatars>(),
        tour: tours == null ? null : ConversationTour(service: tours),
        commandsTour: tours == null
            ? null
            : CommandsTour(
                service: tours,
                isListOpen: () => controller.prompt.isNameList,
                hasRows: () => controller.prompt.hasRows,
              ),
        newTicketDetail: (ticketId) => TicketDetailController(
          ticketId: ticketId,
          tickets: Get.find<TicketRepository>(),
          files: Get.find<FormFileRepository>(),
          connectivity: Get.find<ConnectivityService>(),
        ),
      ),
      tag: id,
    );
    // A home reload takes this screen down first (see HomeReload).
    HomeReload.overlays[id] = (
      retire: controller.retire,
      close: () => Get.delete<ConversationController>(tag: id, force: true),
    );
  }
}
