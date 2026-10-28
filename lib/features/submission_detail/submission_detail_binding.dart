import 'package:get/get.dart';

import 'submission_detail_controller.dart';

class SubmissionDetailBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(
      () =>
          SubmissionDetailController(submissionId: Get.parameters['id'] ?? ''),
    );
  }
}
