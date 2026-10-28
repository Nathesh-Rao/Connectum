import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';

class ProfileController extends GetxController {
  void replayIntroduction() =>
      Get.toNamed(AppRoutes.onboarding, arguments: {'replay': true});
}
