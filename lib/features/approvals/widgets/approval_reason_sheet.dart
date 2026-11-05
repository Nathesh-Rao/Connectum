import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/approval.dart';
import '../approval_reason_controller.dart';
import '../approvals_controller.dart';
import '../approvals_texts.dart';
import '../models/approval_rules.dart';

/// Reject or return: a reason that must be filled before Send, an optional
/// comment, and for a rejected submission whether its author may send it
/// again.
class ApprovalReasonSheet extends StatelessWidget {
  const ApprovalReasonSheet({super.key, required this.form});

  final ApprovalReasonController form;

  static Future<void> show(
    BuildContext context,
    ApprovalsController controller,
    Approval request,
    ApprovalAction action,
  ) {
    final form = ApprovalReasonController(
      request: request,
      action: action,
      onSend: (reason, comment, allowResubmit) => controller.respond(
        request,
        action,
        reason: reason,
        comment: comment,
        allowResubmit: allowResubmit,
      ),
    );
    return AppBottomSheet.show<void>(
      context,
      title: action == ApprovalAction.returnIt
          ? ApprovalsTexts.reasonTitleReturn
          : ApprovalsTexts.reasonTitleReject,
      child: ApprovalReasonSheet(form: form),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(ApprovalsTexts.reasonRequired, style: AppText.readable),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: f.reason,
            label: ApprovalsTexts.reasonLabelField,
            hint: ApprovalsTexts.reasonHint,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            enabled: !f.isSending.value,
            onChanged: f.onReasonChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: f.comment,
            label: ApprovalsTexts.commentLabel,
            hint: ApprovalsTexts.commentHint,
            minLines: 2,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            enabled: !f.isSending.value,
          ),
        ),
        if (f.hasResubmit) ...[
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Row(
              children: [
                const Expanded(
                  child: Text(
                    ApprovalsTexts.allowResubmit,
                    style: AppText.readable,
                  ),
                ),
                Switch(
                  value: f.allowResubmit.value,
                  activeTrackColor: AppColors.accent,
                  onChanged: f.isSending.value
                      ? null
                      : (v) => f.allowResubmit.value = v,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: ApprovalsTexts.send,
            isCentered: true,
            isLoading: f.isSending.value,
            onPressed: f.canSend
                ? () async {
                    final ok = await f.send();
                    if (ok && context.mounted) Navigator.of(context).pop();
                  }
                : null,
          ),
        ),
      ],
    );
  }
}
