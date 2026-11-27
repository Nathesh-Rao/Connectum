import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/log/safe.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_action_bar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../data/models/record_state.dart';
import '../../inbox/approval_texts.dart';
import '../../inbox/models/approval_rules.dart';
import '../../inbox/widgets/approval_reason_sheet.dart';
import '../models/ticket_action_style.dart';
import '../ticket_detail_controller.dart';
import '../tickets_texts.dart';
import 'ticket_action_sheet.dart';

/// The sticky bar at the foot of the record screen: only what applies to this
/// kind of record and this person. The answers of an approval (Approve,
/// Decline, Return, Dismiss), the server's menu (`record.actions`: Send,
/// Update status) and Edit. It never takes more than 45% of the screen; past
/// that it scrolls.
class RecordActionBar extends StatelessWidget {
  const RecordActionBar({super.key, required this.controller});

  final TicketDetailController controller;

  static String labelOf(ApprovalAction a) => switch (a) {
    ApprovalAction.accept => ApprovalTexts.approve,
    ApprovalAction.reject => ApprovalTexts.decline,
    ApprovalAction.returnIt => ApprovalTexts.returnIt,
    ApprovalAction.ignore => ApprovalTexts.dismiss,
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final isBusy = c.isBusy.value || c.isCooling.value;
      final isOpen =
          c.viewState.value == AppViewState.content &&
          !c.isGone.value &&
          !c.isUnopenable.value;
      final answers = isOpen ? c.approvalActions : const <ApprovalAction>[];
      final items = isOpen ? c.items : const <RecordActionItem>[];
      final canEdit = isOpen && c.canEdit;
      if (answers.isEmpty && items.isEmpty && !canEdit) {
        return const SizedBox.shrink();
      }
      final request = c.approval;
      final main = [
        for (final a in answers)
          if (a == ApprovalAction.accept || a == ApprovalAction.reject) a,
      ];
      final more = [
        for (final a in answers)
          if (a != ApprovalAction.accept && a != ApprovalAction.reject) a,
      ];
      return DecoratedBox(
        key: const ValueKey('record-action-bar'),
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.cardLine)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.45,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (main.isNotEmpty)
                  Row(
                    children: [
                      for (var i = 0; i < main.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: main[i] == ApprovalAction.accept
                              ? AppButton.primary(
                                  label: labelOf(main[i]),
                                  isCompact: true,
                                  isCentered: true,
                                  isLoading: isBusy,
                                  onPressed: isBusy
                                      ? null
                                      : () => _answer(context, main[i]),
                                )
                              : AppButton.secondary(
                                  label: labelOf(main[i]),
                                  isDanger: true,
                                  onPressed: isBusy
                                      ? null
                                      : () => _answer(context, main[i]),
                                ),
                        ),
                      ],
                    ],
                  ),
                if (more.isNotEmpty && request != null)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      for (final a in more)
                        AppButton.text(
                          label: labelOf(a),
                          tone: AppTextButtonTone.accent,
                          onPressed: isBusy ? null : () => _answer(context, a),
                        ),
                    ],
                  ),
                if (answers.isNotEmpty && (items.isNotEmpty || canEdit))
                  const SizedBox(height: AppSpacing.xs),
                if (items.isNotEmpty) ...[
                  AppActionBar(
                    items: actionItemsOf(items),
                    layout: AppActionLayout.full,
                    isEnabled: !isBusy,
                    onTap: (item) =>
                        TicketActionSheet.show(context, c, item.id),
                  ),
                  for (final i in items)
                    if (!i.isEnabled && i.why.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xxs),
                        child: Text(
                          '${i.label}: ${i.why}',
                          style: AppText.readable.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                ],
                if (canEdit) ...[
                  if (items.isNotEmpty) const SizedBox(height: AppSpacing.xs),
                  AppButton.secondary(
                    label: TicketsTexts.edit,
                    icon: Icons.edit_outlined,
                    onPressed: isBusy ? null : c.edit,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  void _answer(BuildContext context, ApprovalAction a) {
    final request = controller.approval;
    if (request == null) return;
    if (ApprovalRules.opensSheet(request, a)) {
      ApprovalReasonSheet.showFor(
        context,
        request,
        a,
        (reason, note, allowResubmit) => controller.respond(
          a,
          reason: reason,
          comment: note,
          allowResubmit: allowResubmit,
        ),
      );
    } else {
      fireAndLog('record_action_bar', () => controller.respond(a));
    }
  }
}
