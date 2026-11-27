import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:connectum/data/models/models.dart';
import 'models/approval_rules.dart';

/// The Decline / Return sheet of one request. Made by the sheet opener. For a
/// form the reason must be filled before Send is enabled; a note is always
/// optional. "Allow resubmission" starts off.
class ApprovalReasonController {
  ApprovalReasonController({
    required this.request,
    required this.action,
    required this.onSend,
  });

  final Approval request;
  final ApprovalAction action;

  /// Sends the answer; true when the server took it.
  final Future<bool> Function(String reason, String note, bool allowResubmit)
  onSend;

  final reason = TextEditingController();
  final note = TextEditingController();
  final text = ''.obs;
  final allowResubmit = false.obs;
  final isSending = false.obs;

  bool get isReasonRequired => ApprovalRules.needsReason(request, action);
  bool get hasResubmit => ApprovalRules.offersResubmit(request, action);

  bool get canSend =>
      !isSending.value && ApprovalRules.canSend(request, action, text.value);

  void onReasonChanged(String value) => text.value = value;

  Future<bool> send() async {
    if (!canSend) return false;
    isSending.value = true;
    try {
      return await onSend(
        ApprovalRules.clip(reason.text),
        ApprovalRules.clip(note.text),
        hasResubmit && allowResubmit.value,
      );
    } finally {
      isSending.value = false;
    }
  }

  void dispose() {
    reason.dispose();
    note.dispose();
  }
}
