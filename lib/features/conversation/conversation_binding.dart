import 'package:get/get.dart';

import '../../data/repositories/people_avatars.dart';

import '../../core/routes/home_reload.dart';
import '../../data/ai/ai_repository.dart';
import '../../data/ai/ai_setup_cache.dart';
import '../../data/attachment_cache.dart';
import '../../data/repositories/attachment_repository.dart';
import '../../data/repositories/command_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/form_file_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/repositories/typing_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../home_shell/home_shell_controller.dart';
import '../tickets/ticket_detail_controller.dart';
import 'conversation_controller.dart';

/// Puts one controller per conversation id (its tag), so another route's
/// disposal can never delete it.
class ConversationBinding extends Bindings {
  @override
  void dependencies() {
    final id = Uri.decodeComponent(Get.parameters['id'] ?? '');
    final controller = Get.put(
      ConversationController(
        conversationId: id,
        messages: Get.find<MessageRepository>(),
        conversations: Get.find<ConversationRepository>(),
        presence: Get.find<PresenceRepository>(),
        typing: Get.find<TypingRepository>(),
        submissions: Get.find<SubmissionRepository>(),
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
        newTicketDetail: (ticketId) => TicketDetailController(
          ticketId: ticketId,
          tickets: Get.find<TicketRepository>(),
          people: Get.find<GroupRepository>(),
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
