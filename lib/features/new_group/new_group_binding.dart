import 'package:get/get.dart';

import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/group_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import 'new_group_controller.dart';

/// Opened with no arguments to create a group, or with a group's name as the
/// argument to add people to it.
class NewGroupBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.put(
      NewGroupController(
        groups: Get.find<GroupRepository>(),
        conversations: Get.find<ConversationRepository>(),
        connectivity: Get.find<ConnectivityService>(),
        store: Get.find<SessionStore>(),
        existingGroup: args is String ? args : null,
      ),
    );
  }
}
