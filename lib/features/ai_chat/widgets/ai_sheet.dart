import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_pill_bar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/ai/ai_models.dart';
import '../ai_summary_controller.dart';
import '../ai_texts.dart';
import 'ai_notice_dialog.dart';
import 'ai_rich_text.dart';

/// The title of the sheet: a round tinted icon and the name.
class AiSheetTitle extends StatelessWidget {
  const AiSheetTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: AppColors.violetTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            size: 20,
            color: AppColors.violet,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(AiTexts.title, style: AppText.title)),
      ],
    );
  }
}

/// The body of the sheet: the option list, the range step, then the loading,
/// result and error views, switched in place.
class AiSheet extends StatelessWidget {
  const AiSheet({super.key, required this.controller, required this.onClose});

  final AiSummaryController controller;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => AnimatedSize(
        duration: AppDurations.sheetResize,
        curve: AppCurves.out,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: AppDurations.fast,
          switchInCurve: AppCurves.out,
          child: KeyedSubtree(
            key: ValueKey(c.phase.value),
            child: switch (c.phase.value) {
              AiPhase.menu => _Menu(controller: c),
              AiPhase.setup => _RangeStep(controller: c),
              AiPhase.loading => _Loading(controller: c),
              AiPhase.result => _Result(controller: c, onClose: onClose),
              AiPhase.error => _Problem(
                controller: c,
                kind: c.error.value ?? AiErrorKind.failed,
                onClose: onClose,
              ),
              AiPhase.cancelled => _StateBlock(
                icon: Icons.block,
                title: AiTexts.cancelledTitle,
                text: AiTexts.cancelledText,
                actionLabel: 'Start again',
                onAction: c.openSetup,
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: AppTones.slate.tint,
      borderRadius: AppRadius.controlAll,
    ),
    child: Icon(icon, size: 18, color: AppTones.slate.strong),
  );
}

class _Menu extends StatelessWidget {
  const _Menu({required this.controller});

  final AiSummaryController controller;

  @override
  Widget build(BuildContext context) {
    final summary = _summaryRow();
    if (!controller.isCare) return summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summary,
        const Divider(height: AppSpacing.md, color: AppColors.line),
        _AskBox(controller: controller),
      ],
    );
  }

  Widget _summaryRow() {
    return InkWell(
      onTap: controller.openSetup,
      borderRadius: AppRadius.controlAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            const _IconChip(icon: Icons.summarize_outlined),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.isCare
                        ? AiTexts.careSummarize
                        : AiTexts.summarize,
                    style: AppText.bodyStrong,
                  ),
                  Text(
                    controller.isCare
                        ? AiTexts.careSummarizeHint
                        : AiTexts.summarizeHint,
                    style: AppText.readable.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.rowChevron),
          ],
        ),
      ),
    );
  }
}

/// The typed question of a care thread: one field and a send button.
class _AskBox extends StatefulWidget {
  const _AskBox({required this.controller});

  final AiSummaryController controller;

  @override
  State<_AskBox> createState() => _AskBoxState();
}

class _AskBoxState extends State<_AskBox> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final q = _text.text;
    if (q.trim().isEmpty) return;
    _text.clear();
    widget.controller.ask(q);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AiTexts.askHeading,
          style: AppText.readable.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppTextField(
          controller: _text,
          hint: AiTexts.askHint,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          suffix: IconButton(
            tooltip: AiTexts.askSend,
            icon: const Icon(Icons.send_rounded, color: AppColors.violet),
            onPressed: _send,
          ),
        ),
      ],
    );
  }
}

class _RangeStep extends StatelessWidget {
  const _RangeStep({required this.controller});

  final AiSummaryController controller;

  Future<void> _pickRange(BuildContext context, AiRange value) async {
    final c = controller;
    if (value != AiRange.date) return c.pick(value);
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: c.date.value ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (day != null) c.pickDate(day);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => c.agents.length < 2
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI',
                        style: AppText.readable.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AppPillBar(
                        pills: [
                          for (final a in c.agents) AppPill(label: a.name),
                        ],
                        selected: c.agents.indexWhere(
                          (a) => a.id == c.agent.value?.id,
                        ),
                        onSelected: (i) => c.pickAgent(c.agents[i]),
                      ),
                    ],
                  ),
                ),
        ),
        if (c.isCare)
          Text(
            AiTexts.careNote,
            style: AppText.readable.copyWith(color: AppColors.muted),
          )
        else ...[
          Text(
            'From',
            style: AppText.readable.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Obx(
            () => AppPillBar(
              pills: [
                for (final r in AiRange.values)
                  AppPill(
                    label: r == AiRange.date && c.date.value != null
                        ? _shortDate(c.date.value!)
                        : r.label,
                  ),
              ],
              selected: c.range.value.index,
              onSelected: (i) => _pickRange(context, AiRange.values[i]),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: 'Summarize',
            isCentered: true,
            onPressed: c.canSummarize ? () => c.summarize() : null,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          c.privacyText,
          textAlign: TextAlign.center,
          style: AppText.readable.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(label: 'Back', onPressed: c.backToMenu),
      ],
    );
  }

  static String _shortDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

class _Loading extends StatelessWidget {
  const _Loading({required this.controller});

  final AiSummaryController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.md),
        const Center(child: AppSpinner(size: AppSpinnerSize.lg)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AiTexts.summarizing,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: AppColors.muted),
        ),
        Obx(
          () => c.text.value.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _SummaryCard(text: c.text.value),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.secondary(label: 'Cancel', onPressed: c.cancel),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardAll,
      border: Border.all(color: AppColors.line),
    ),
    child: AiRichText(text),
  );
}

class _Result extends StatelessWidget {
  const _Result({required this.controller, required this.onClose});

  final AiSummaryController controller;
  final VoidCallback onClose;

  Future<void> _share(BuildContext context) async {
    final isConfirmed = await AiNoticeDialog.confirm(
      context,
      title: AiTexts.shareTitle,
      text: AiTexts.shareText,
      preview: controller.sharePreview,
      confirmLabel: 'Post',
    );
    if (isConfirmed && await controller.share()) onClose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final range = c.usedLabel.value;
    final count = c.messageCount.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (range.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: const BoxDecoration(
                color: AppColors.violetTint,
                borderRadius: AppRadius.pillAll,
              ),
              child: Text(
                count == null ? range : '$range · $count messages',
                style: AppText.caption.copyWith(color: AppColors.primaryStrong),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        _SummaryCard(text: c.text.value),
        if (c.isTruncated.value)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              AiTexts.careTruncated,
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
          ),
        if (c.isPatientView.value)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              AiTexts.patientScope,
              style: AppText.caption.copyWith(color: AppColors.muted),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 12,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                AiTexts.caption,
                style: AppText.caption.copyWith(color: AppColors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (!c.isAnswer) ...[
          Obx(
            () => AppButton.primary(
              label: 'Share in chat',
              icon: Icons.send_rounded,
              isCentered: true,
              onPressed: c.isSharing.value ? null : () => _share(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                label: 'Copy',
                icon: Icons.copy_rounded,
                onPressed: c.copy,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: AppButton.secondary(
                label: 'Regenerate',
                icon: Icons.refresh_rounded,
                onPressed: () => c.retry(),
              ),
            ),
          ],
        ),
        AppButton.text(label: 'Close', onPressed: onClose),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.controller,
    required this.kind,
    required this.onClose,
  });

  final AiSummaryController controller;
  final AiErrorKind kind;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (icon, label, onTap) = switch (kind) {
      AiErrorKind.offline ||
      AiErrorKind.serverTimeout ||
      AiErrorKind.providerUnreachable => (
        Icons.wifi_off_rounded,
        'Retry',
        () => c.retry(),
      ),
      AiErrorKind.careNotFound || AiErrorKind.careNotStarted => (
        Icons.person_off_outlined,
        'Close',
        onClose,
      ),
      AiErrorKind.noMessages || AiErrorKind.tooLarge when c.isCare => (
        Icons.chat_bubble_outline_rounded,
        'Close',
        onClose,
      ),
      AiErrorKind.noMessages || AiErrorKind.tooLarge => (
        kind == AiErrorKind.noMessages
            ? Icons.chat_bubble_outline_rounded
            : Icons.unfold_less_rounded,
        'Change range',
        c.changeRange,
      ),
      AiErrorKind.rateLimited ||
      AiErrorKind.agentBusy ||
      AiErrorKind.providerRateLimited ||
      AiErrorKind.providerBusy => (
        Icons.hourglass_empty_rounded,
        'Try again',
        () => c.retry(),
      ),
      AiErrorKind.timeout ||
      AiErrorKind.failed ||
      AiErrorKind.badRequest ||
      AiErrorKind.emptyAnswer => (
        Icons.error_outline_rounded,
        'Retry',
        () => c.retry(),
      ),
      _ => (Icons.lock_outline_rounded, 'Close', onClose),
    };
    return _StateBlock(
      icon: icon,
      title: AiTexts.errorTitle(kind),
      text: c.errorText(kind, c.errorDetail),
      actionLabel: label,
      onAction: onTap,
    );
  }
}

class _StateBlock extends StatelessWidget {
  const _StateBlock({
    required this.icon,
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.violetTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: AppColors.violet),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(title, textAlign: TextAlign.center, style: AppText.bodyStrong),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          text,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.primary(
          label: actionLabel,
          isCentered: true,
          onPressed: onAction,
        ),
      ],
    );
  }
}
