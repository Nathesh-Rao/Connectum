import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_detail_row.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/models/approval.dart';
import '../approvals_controller.dart';
import '../approvals_texts.dart';
import '../models/approval_rules.dart';
import 'approval_reason_sheet.dart';
import 'approval_tile.dart';

/// One request in full, with only the buttons this person may use. Read-only
/// when they cannot answer it. It follows the list, so an answer or an event
/// shows here at once.
class ApprovalDetailSheet extends StatelessWidget {
  const ApprovalDetailSheet({
    super.key,
    required this.controller,
    required this.requestId,
    required this.initial,
  });

  final ApprovalsController controller;
  final int requestId;
  final Approval initial;

  static Future<void> show(
    BuildContext context,
    ApprovalsController controller,
    Approval request,
  ) => AppBottomSheet.show<void>(
    context,
    title: ApprovalsTexts.detailTitle,
    child: ApprovalDetailSheet(
      controller: controller,
      requestId: request.id,
      initial: request,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final r = c.find(requestId) ?? initial;
      final actions = ApprovalRules.actionsFor(r);
      final busy = c.isBusy.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(ApprovalTile.headline(r), style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: AppSpacing.xs,
              children: [
                AppTag(label: ApprovalsTexts.typeLabel(r.type)),
                AppTag(
                  label: ApprovalsTexts.statusLabel(r.status),
                  tone: r.isPending ? AppTagTone.accent : AppTagTone.neutral,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppDetailRow(caption: ApprovalsTexts.from, value: r.fromLabel),
          if (r.subjectName.isNotEmpty && r.subject != r.from)
            AppDetailRow(caption: ApprovalsTexts.about, value: r.subjectName),
          AppDetailRow(
            caption: ApprovalsTexts.sent,
            value: RelativeTime.label(r.createdTs, DateTime.now()),
          ),
          if (r.stage != null && r.stages != null)
            AppDetailRow(
              caption: ApprovalsTexts.stage,
              value: '${r.stage} / ${r.stages}',
            ),
          for (final line in r.lines)
            AppDetailRow(caption: line.caption, value: line.value),
          if (r.isOutgoing && r.isPending && r.approvers.isNotEmpty)
            AppDetailRow(
              caption: ApprovalsTexts.waitingFor,
              value: r.approvers.join(', '),
            ),
          if (!r.isPending && r.resolvedByLabel.isNotEmpty)
            AppDetailRow(
              caption: ApprovalsTexts.answeredBy,
              value: r.resolvedByDesignation == null
                  ? r.resolvedByLabel
                  : '${r.resolvedByLabel} · ${r.resolvedByDesignation}',
            ),
          if (r.reason.isNotEmpty)
            AppDetailRow(caption: ApprovalsTexts.reasonLabel, value: r.reason),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _button(context, c, r, action, busy),
              ),
          ],
        ],
      );
    });
  }

  Widget _button(
    BuildContext context,
    ApprovalsController c,
    Approval r,
    ApprovalAction action,
    bool busy,
  ) {
    final needsReason = ApprovalRules.needsReason(action);
    void onTap() => needsReason
        ? ApprovalReasonSheet.show(context, c, r, action)
        : c.respond(r, action);
    final label = switch (action) {
      ApprovalAction.accept => ApprovalsTexts.accept,
      ApprovalAction.reject => ApprovalsTexts.reject,
      ApprovalAction.returnIt => ApprovalsTexts.returnIt,
      ApprovalAction.ignore => ApprovalsTexts.ignore,
    };
    return action == ApprovalAction.accept
        ? AppButton.primary(
            label: label,
            isCentered: true,
            isLoading: busy,
            onPressed: busy ? null : onTap,
          )
        : AppButton.secondary(
            label: label,
            isDanger: action == ApprovalAction.reject,
            onPressed: busy ? null : onTap,
          );
  }
}
