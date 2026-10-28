import 'package:get/get.dart';

import '../../data/repositories/conversation_repository.dart';
import '../ai_agents/ai_agents_binding.dart';
import '../chats/chats_binding.dart';
import '../profile/profile_binding.dart';
import '../submissions/submissions_binding.dart';
import 'home_shell_controller.dart';

class HomeShellBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(
      HomeShellController(conversations: Get.find<ConversationRepository>()),
    );
    ChatsBinding().dependencies();
    AiAgentsBinding().dependencies();
    SubmissionsBinding().dependencies();
    ProfileBinding().dependencies();
  }
}
