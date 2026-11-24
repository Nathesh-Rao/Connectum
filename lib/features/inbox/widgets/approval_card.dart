import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/models/approval.dart';
import '../approval_texts.dart';
import '../inbox_approvals_controller.dart';
import '../models/approval_pane.dart';
import '../models/approval_rules.dart';
import 'approval_reason_sheet.dart';

/// The colours of each state, from the theme's tones (never a hex here).
AppTone approvalToneOf(Approval a) => switch (ApprovalPane.stateOf(a)) {
  ApprovalState.pending =>
    ApprovalPane.isWaitingForMe(a) ? AppTones.yellow : AppTones.violet,
  ApprovalState.approved => AppTones.green,
  ApprovalState.rejected => AppTones.red,
  ApprovalState.other => AppTones.slate,
};

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

/// One request of the Approvals pane, laid out like an Inbox card: a tinted
/// band with the sender's picture (or the kind's icon), the title, the date
/// and the tag; name and value lines; the answer buttons at the foot. Only
/// the buttons the server lets the person use (`canRespond`) show.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.controller,
    required this.request,
  });

  final InboxApprovals controller;
  final Approval request;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final a = request;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final tone = approvalToneOf(a);
    final actions = ApprovalRules.actionsFor(a);
    return Semantics(
      container: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: const BorderSide(color: AppColors.cardLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Band(controller: c, request: a, tone: tone),
            const Divider(height: 1, color: AppColors.cardLine),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: AppSpacing.inboxCardHeight * scale * 0.6,
              ),
              child: _Body(request: a),
            ),
            if (actions.isNotEmpty) ...[
              const Divider(height: 1, color: AppColors.cardLine),
              _Foot(controller: c, request: a, actions: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({
    required this.controller,
    required this.request,
    required this.tone,
  });

  final InboxApprovals controller;
  final Approval request;
  final AppTone tone;

  String get _date {
    final ts = request.createdTs;
    if (ts <= 0) return '';
    return '${ChatTime.date(ts)}, ${ChatTime.time(ts)}';
  }

  @override
  Widget build(BuildContext context) {
    final tag = ApprovalPane.tagOf(request);
    return ColoredBox(
      color: tone.tintMedium,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Face(controller: controller, request: request, tone: tone),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ApprovalPane.titleOf(request),
                    style: AppText.bodyStrong.copyWith(color: AppColors.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_date.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _date,
                      style: AppText.caption.copyWith(color: AppColors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (tag.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _Tag(text: tag, tone: tone),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.controller,
    required this.request,
    required this.tone,
  });

  final InboxApprovals controller;
  final Approval request;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.inboxFaceWidth,
      child: Obx(() {
        final picture = controller.pictureOf(request);
        final name = controller.whoLabelOf(request);
        return Column(
          children: [
            if (picture != null)
              AppAvatar(
                name: name,
                size: AppSpacing.inboxFaceSize,
                picture: picture,
              )
            else
              Container(
                width: AppSpacing.inboxFaceSize,
                height: AppSpacing.inboxFaceSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.white,
                  border: Border.all(color: tone.tintStrong),
                ),
                child: Icon(
                  approvalIconOf(request),
                  size: AppSpacing.inboxFaceSize / 2,
                  color: tone.strong,
                ),
              ),
            if (name.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                name,
                style: AppText.caption.copyWith(color: AppColors.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
      }),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.tone});

  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tone.tintStrong,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        text,
        style: AppText.readableStrong.copyWith(color: tone.strong),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.request});

  final Approval request;

  @override
  Widget build(BuildContext context) {
    final rows = ApprovalPane.detailRows(request);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      r.$1,
                      style: AppText.readable.copyWith(color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    flex: 7,
                    child: Text(
                      r.$2,
                      style: AppText.readable.copyWith(color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Foot extends StatelessWidget {
  const _Foot({
    required this.controller,
    required this.request,
    required this.actions,
  });

  final InboxApprovals controller;
  final Approval request;
  final List<ApprovalAction> actions;

  static String labelOf(ApprovalAction a) => switch (a) {
    ApprovalAction.accept => ApprovalTexts.approve,
    ApprovalAction.reject => ApprovalTexts.decline,
    ApprovalAction.returnIt => ApprovalTexts.returnIt,
    ApprovalAction.ignore => ApprovalTexts.dismiss,
  };

  void _tap(BuildContext context, ApprovalAction a) {
    if (ApprovalRules.opensSheet(request, a)) {
      ApprovalReasonSheet.show(context, controller, request, a);
    } else {
      controller.respond(request, a);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Obx(() {
        final isBusy = controller.busy.contains(request.id);
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final a in actions)
              a == ApprovalAction.accept
                  ? AppButton.primary(
                      label: labelOf(a),
                      isCompact: true,
                      isLoading: isBusy,
                      onPressed: isBusy ? null : () => _tap(context, a),
                    )
                  : AppButton.secondary(
                      label: labelOf(a),
                      isDanger: a == ApprovalAction.reject,
                      onPressed: isBusy ? null : () => _tap(context, a),
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
