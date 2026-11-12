import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_pill_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../data/ai/ai_models.dart';
import '../../data/ai/fake_ai_repository.dart';
import '../ai_chat/ai_entry.dart';
import '../ai_chat/ai_summary_message_format.dart';
import '../ai_chat/ai_texts.dart';
import '../ai_chat/widgets/ai_header_button.dart';
import '../ai_chat/widgets/ai_notice_dialog.dart';
import '../ai_chat/widgets/ai_rich_text.dart';
import 'debug_ai_controller.dart';

class DebugAiView extends GetView<DebugAiController> {
  const DebugAiView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          const Text('In-chat AI (fake)', style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Pick the setup state and the answer, then tap the icon. The fake '
            'sends nothing; "Real server" asks the real one.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: AiHeaderButton(onPressed: () => openAi(context, c.summary)),
          ),
          const Text('Setup', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Obx(
            () => AppPillBar(
              pills: [
                for (final s in AiSetupState.values) AppPill(label: s.name),
              ],
              selected: c.setupState.value.index,
              onSelected: (i) => c.setSetup(AiSetupState.values[i]),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Answer', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Obx(
            () => AppPillBar(
              pills: [
                for (final s in FakeAiScenario.values) AppPill(label: s.name),
              ],
              selected: c.scenario.value.index,
              onSelected: (i) => c.setScenario(FakeAiScenario.values[i]),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const SizedBox(height: AppSpacing.xs),
          Obx(
            () => AppPillBar(
              pills: [
                for (final k in AiErrorKind.values) AppPill(label: k.name),
              ],
              selected: c.scenario.value == FakeAiScenario.failure
                  ? c.failure.value.index
                  : -1,
              onSelected: (i) => c.setFailure(AiErrorKind.values[i]),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Care thread question', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Obx(
            () => AppPillBar(
              pills: [
                for (final t in FakeCareThread.values) AppPill(label: t.name),
              ],
              selected: c.isCare.value ? c.careThread.value.index : -1,
              onSelected: (i) => c.setCare(FakeCareThread.values[i]),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Wrap(
              spacing: AppSpacing.xs,
              children: [
                _Toggle('3 agents', c.agentCount.value > 1, c.toggleAgents),
                _Toggle(
                  'Setup fails',
                  c.setupFailure.value != null,
                  c.toggleSetupFailure,
                ),
                _Toggle('Care thread', c.isCare.value, c.toggleCare),
                _Toggle('E2E chat', c.isE2e.value, c.toggleE2e),
                _Toggle('I am an admin', c.isAdmin.value, c.toggleAdmin),
                _Toggle('Offline', c.isOffline.value, c.toggleOffline),
                _Toggle('Streaming', c.isStreaming.value, c.toggleStreaming),
                _Toggle('Real server', c.isReal.value, c.toggleReal),
                _Toggle(
                  'Send fails',
                  c.isSendFailing.value,
                  c.toggleSendFailing,
                ),
              ],
            ),
          ),
          Obx(
            () => c.isE2e.value
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: SelectableText(
                      DebugAiController.e2eSample,
                      style: AppText.caption,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Dialogs', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: AiTexts.setupTitle,
            onPressed: () => AiNoticeDialog.show(
              context,
              title: AiTexts.setupTitle,
              text: AiTexts.setupText(isAdmin: c.isAdmin.value),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Post summary confirm',
            onPressed: () => AiNoticeDialog.confirm(
              context,
              title: AiTexts.shareTitle,
              text: AiTexts.shareText,
              preview: c.summary.sharePreview,
              confirmLabel: 'Post',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Error texts', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          for (final k in AiErrorKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Obx(
                () => Text(
                  '${k.name}: ${AiTexts.errorBody(k, isAdmin: c.isAdmin.value)}',
                  style: AppText.readable,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Charts', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          for (final e in fakeChartSamples.entries) ...[
            Text(e.key.name, style: AppText.readable),
            const SizedBox(height: AppSpacing.xxs),
            AiRichText(e.value),
            const SizedBox(height: AppSpacing.sm),
          ],
          const Text('Posted text', style: AppText.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          const _Preview('Short', _sample),
          _Preview('Long (split)', _long),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.posted.isNotEmpty)
                  const Text('Posted by Share', style: AppText.bodyStrong),
                for (final m in c.posted) _Bubble(m),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _sample =
    '**Decisions**\n- Ship on Friday\n- Ana owns the release, ping @ana';
final _long = List.generate(
  40,
  (i) => '- Point ${i + 1}: the team agreed to review the plan with @ravi.',
).join('\n');

class _Preview extends StatelessWidget {
  const _Preview(this.label, this.text);

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = AiSummaryMessageFormat.build(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${parts.length} message(s)', style: AppText.readable),
        for (final p in parts) _Bubble(p),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardAll,
      border: Border.all(color: AppColors.line),
    ),
    child: Text(text, style: AppText.readable),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.isOn, this.onTap);

  final String label;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: isOn,
    onSelected: (_) => onTap(),
  );
}
