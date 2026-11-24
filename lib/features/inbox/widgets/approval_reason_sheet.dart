import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/approval.dart';
import '../approval_reason_controller.dart';
import '../approval_texts.dart';
import '../inbox_approvals_controller.dart';
import '../models/approval_rules.dart';

/// Decline or return: a reason (required for a form), an optional note, and
/// for a declined form whether its author may send it again.
class ApprovalReasonSheet extends StatelessWidget {
  const ApprovalReasonSheet({super.key, required this.form});

  final ApprovalReasonController form;

  static Future<void> show(
    BuildContext context,
    InboxApprovals controller,
    Approval request,
    ApprovalAction action,
  ) {
    final form = ApprovalReasonController(
      request: request,
      action: action,
      onSend: (reason, note, allowResubmit) => controller.respond(
        request,
        action,
        reason: reason,
        comment: note,
        allowResubmit: allowResubmit,
      ),
    );
    return AppBottomSheet.show<void>(
      context,
      title: action == ApprovalAction.returnIt
          ? ApprovalTexts.returnTitle
          : ApprovalTexts.declineTitle,
      child: ApprovalReasonSheet(form: form),
      onDispose: form.dispose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = form;
    final limit = [LengthLimitingTextInputFormatter(ApprovalRules.maxText)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.isReasonRequired) ...[
          const Text(ApprovalTexts.reasonRequired, style: AppText.readable),
          const SizedBox(height: AppSpacing.md),
        ],
        Obx(
          () => AppTextField(
            controller: f.reason,
            label: ApprovalTexts.reasonLabel,
            hint: ApprovalTexts.reasonHint,
            minLines: 2,
            maxLines: 5,
            inputFormatters: limit,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            enabled: !f.isSending.value,
            onChanged: f.onReasonChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: f.note,
            label: ApprovalTexts.noteLabel,
            hint: ApprovalTexts.noteHint,
            minLines: 2,
            maxLines: 5,
            inputFormatters: limit,
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
                    ApprovalTexts.allowResubmit,
                    style: AppText.readable,
                  ),
                ),
                Switch(
                  value: f.allowResubmit.value,
                  activeTrackColor: AppColors.primaryBright,
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
            label: ApprovalTexts.send,
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
