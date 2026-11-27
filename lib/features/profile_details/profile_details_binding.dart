import 'package:get/get.dart';

import 'package:connectum/data/repositories/repositories.dart';
import 'profile_details_controller.dart';

class ProfileDetailsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () => ProfileDetailsController(repository: Get.find<ProfileRepository>()),
    );
  }
}
