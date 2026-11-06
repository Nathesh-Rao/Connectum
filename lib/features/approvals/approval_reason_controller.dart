import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/models/approval.dart';
import 'models/approval_rules.dart';

/// The reason / comment sheet of one reject or return. Made by the sheet
/// opener; the reason must not be empty before Send is enabled.
class ApprovalReasonController {
  ApprovalReasonController({
    required this.request,
    required this.action,
    required this.onSend,
  });

  final Approval request;
  final ApprovalAction action;

  /// Sends the answer; true when the server took it.
  final Future<bool> Function(
    String reason,
    String comment,
    bool? allowResubmit,
  )
  onSend;

  final reason = TextEditingController();
  final comment = TextEditingController();
  final text = ''.obs;
  final allowResubmit = true.obs;
  final isSending = false.obs;

  bool get hasResubmit => ApprovalRules.offersResubmit(request, action);

  bool get canSend =>
      !isSending.value && ApprovalRules.canSend(action, text.value);

  void onReasonChanged(String value) => text.value = value;

  Future<bool> send() async {
    if (!canSend) return false;
    isSending.value = true;
    try {
      return await onSend(
        reason.text.trim(),
        comment.text.trim(),
        hasResubmit ? allowResubmit.value : null,
      );
    } finally {
      isSending.value = false;
    }
  }

  void dispose() {
    reason.dispose();
    comment.dispose();
  }
}
