import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_text.dart';
import '../../core/widgets/app_scaffold.dart';
import 'submission_detail_controller.dart';

class SubmissionDetailView extends GetView<SubmissionDetailController> {
  const SubmissionDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Center(
        child: Text(
          'Submission Detail ${controller.submissionId}',
          style: AppText.title,
        ),
      ),
    );
  }
}
