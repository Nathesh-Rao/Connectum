import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import '../../data/session_store.dart';
import 'profile_status_controller.dart';

class ProfileStatusBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ProfileStatusController(
        repository: Get.find<ProfileRepository>(),
        profiles: Get.find<PeopleProfiles>(),
        avatars: Get.find<PeopleAvatars>(),
        store: Get.find<SessionStore>(),
      ),
    );
  }
}
