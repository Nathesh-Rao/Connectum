import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import '../approval_texts.dart';
import '../inbox_approvals_controller.dart';
import '../inbox_tour_demo.dart';
import '../models/approval_pane.dart';
import '../models/inbox_card_rows.dart';
import '../models/approval_rules.dart';
import 'approval_reason_sheet.dart';
import 'inbox_card_frame.dart';

/// The colours of each state, from the theme's tones (never a hex here).
AppTone approvalToneOf(Approval a) => approvalStatusOf(a).tone;

/// The icon of a kind, shown when the sender has no picture.
IconData approvalIconOf(Approval a) => switch (a.type) {
  'onboarding' => Icons.person_add_alt_1_outlined,
  'membership' || 'associate' => Icons.people_outline,
  'handover' => Icons.swap_horiz,
  'group_invite' => Icons.group_add_outlined,
  'host_transfer' => Icons.sync_alt,
  'submission' => Icons.fact_check_outlined,
  _ => Icons.mail_outline,
};

/// Where a request stands, as the status circle of its card.
InboxCardStatus approvalStatusOf(Approval a) =>
    switch (ApprovalPane.stateOf(a)) {
      ApprovalState.pending =>
        ApprovalPane.isWaitingForMe(a)
            ? InboxCardStatus.pending
            : InboxCardStatus.waiting,
      ApprovalState.approved => InboxCardStatus.completed,
      ApprovalState.rejected => InboxCardStatus.rejected,
      ApprovalState.other => InboxCardStatus.closed,
    };

/// One request of the Approvals pane or the Inbox list, as a card
/// (`InboxCardFrame`): the sender's picture (or the kind's icon), the title,
/// the sender's name, `#id`, date and time; the status circle; rows with an
/// icon and "Show more"; the status as a strip above the answer buttons. Only
/// the buttons the server lets the person use (`canRespond`) show.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.controller,
    required this.request,
    this.sample,
  });

  final InboxApprovals controller;
  final Approval request;

  /// The first-run tour's sample: the buttons answer nothing and the card's
  /// open state is the sample's own.
  final InboxTourDemo? sample;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final a = request;
    final demo = sample;
    final actions = ApprovalRules.actionsFor(a);
    final key = 'a${a.id}';
    final word = ApprovalPane.statusWord(a);
    return Obx(
      () => InboxCardFrame(
        leading: _Face(controller: c, request: a),
        title: ApprovalPane.titleOf(a),
        name: c.whoLabelOf(a),
        idText: '#${a.id}',
        ts: a.createdTs,
        status: approvalStatusOf(a),
        statusLabel: word,
        strip: word,
        rows: [
          for (final (n, v) in ApprovalPane.detailRows(a))
            InboxCardRow.plain(n, v),
        ],
        isExpanded: demo?.isOpen(key) ?? c.isExpanded(key),
        onToggle: () => demo != null ? demo.toggle(key) : c.toggleExpanded(key),
        footer: actions.isEmpty
            ? null
            : _Foot(
                controller: c,
                request: a,
                actions: actions,
                isSample: demo != null,
              ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.controller, required this.request});

  final InboxApprovals controller;
  final Approval request;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final picture = controller.pictureOf(request);
      if (picture == null) return _icon();
      return AppAvatar(
        name: controller.whoLabelOf(request),
        size: AppSpacing.inboxFaceSize,
        picture: picture,
      );
    });
  }

  Widget _icon() {
    final tone = approvalStatusOf(request).tone;
    return Container(
      width: AppSpacing.inboxFaceSize,
      height: AppSpacing.inboxFaceSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.tint,
        border: Border.all(color: tone.tintStrong),
      ),
      child: Icon(
        approvalIconOf(request),
        size: AppSpacing.inboxFaceSize / 2,
        color: tone.strong,
      ),
    );
  }
}

/// Approve and Decline side by side; Return (forms) and Dismiss under them as
/// plain text. Every button waits while an answer is on its way.
class _Foot extends StatelessWidget {
  const _Foot({
    required this.controller,
    required this.request,
    required this.actions,
    this.isSample = false,
  });

  final InboxApprovals controller;
  final Approval request;
  final List<ApprovalAction> actions;
  final bool isSample;

  static String labelOf(ApprovalAction a) => switch (a) {
    ApprovalAction.accept => ApprovalTexts.approve,
    ApprovalAction.reject => ApprovalTexts.decline,
    ApprovalAction.returnIt => ApprovalTexts.returnIt,
    ApprovalAction.ignore => ApprovalTexts.dismiss,
  };

  void _tap(BuildContext context, ApprovalAction a) {
    if (isSample) return;
    if (ApprovalRules.opensSheet(request, a)) {
      ApprovalReasonSheet.show(context, controller, request, a);
    } else {
      controller.respond(request, a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final main = [
      for (final a in actions)
        if (a == ApprovalAction.accept || a == ApprovalAction.reject) a,
    ];
    final more = [
      for (final a in actions)
        if (a != ApprovalAction.accept && a != ApprovalAction.reject) a,
    ];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Obx(() {
        final isBusy = controller.busy.contains(request.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                  : () => _tap(context, main[i]),
                            )
                          : AppButton.secondary(
                              label: labelOf(main[i]),
                              isDanger: true,
                              onPressed: isBusy
                                  ? null
                                  : () => _tap(context, main[i]),
                            ),
                    ),
                  ],
                ],
              ),
            if (more.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  for (final a in more)
                    AppButton.text(
                      label: labelOf(a),
                      tone: AppTextButtonTone.accent,
                      onPressed: isBusy ? null : () => _tap(context, a),
                    ),
                ],
              ),
          ],
        );
      }),
    );
  }
}

/// Wraps a card so that, once answered and no longer in the list, it slides
/// out (size and opacity) before the list is read again.
class ApprovalSlot extends StatelessWidget {
  const ApprovalSlot({
    super.key,
    required this.controller,
    required this.request,
    this.isLeavingNow,
  });

  final InboxApprovals controller;
  final Approval request;

  /// Says whether the card has left the list it is drawn in (the Inbox list
  /// has its own rules); the pane's own filter when null.
  final bool Function()? isLeavingNow;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isLeaving = isLeavingNow?.call() ?? controller.isLeaving(request);
      return AnimatedSize(
        duration: AppDurations.fast,
        curve: AppCurves.out,
        alignment: Alignment.topCenter,
        child: isLeaving
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ApprovalCard(controller: controller, request: request),
              ),
      );
    });
  }
}
