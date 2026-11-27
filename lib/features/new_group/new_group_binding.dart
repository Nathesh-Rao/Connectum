import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../data/session_store.dart';
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
