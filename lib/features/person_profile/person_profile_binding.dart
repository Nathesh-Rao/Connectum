import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'models/person_card.dart';
import 'person_profile_controller.dart';

/// The card comes in the route arguments; the username is also in the path,
/// so a link with no arguments still opens a profile of what is held.
class PersonProfileBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    final username = Uri.decodeComponent(Get.parameters['username'] ?? '');
    Get.lazyPut(
      () => PersonProfileController(
        card: args is PersonCard ? args : PersonCard(username: username),
        profiles: Get.find<PeopleProfiles>(),
        presence: Get.find<PresenceRepository>(),
        avatars: Get.find<PeopleAvatars>(),
      ),
    );
  }
}
