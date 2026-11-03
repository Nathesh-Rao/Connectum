import 'package:get/get.dart';

import '../../data/repositories/submission_repository.dart';
import '../../data/session_store.dart';
import 'submission_detail_controller.dart';

/// One controller per submission id (its tag), so a detail opened from
/// another route can never share or delete this one.
class SubmissionDetailBinding extends Bindings {
  @override
  void dependencies() {
    final id = Uri.decodeComponent(Get.parameters['id'] ?? '');
    Get.put(
      SubmissionDetailController(
        submissionId: id,
        convId: Get.parameters['conv'],
        msgId: Get.parameters['msg'],
        submissions: Get.find<SubmissionRepository>(),
        store: Get.find<SessionStore>(),
      ),
      tag: id,
    );
  }
}
