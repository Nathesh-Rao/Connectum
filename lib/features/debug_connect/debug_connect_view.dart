import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_connect.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/connect_code.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import 'debug_connect_controller.dart';

class DebugConnectView extends GetView<DebugConnectController> {
  const DebugConnectView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Debug: connect links', style: AppText.heading),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Type or paste a link to see how it is read. Nothing is sent to the server.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: c.input,
            label: 'Link or code',
            hint: 'https://connectum.app/connect/KVZDHDQD?org=CMYDZ063',
            onSubmitted: (_) => c.read(),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.primary(
            label: 'Read it',
            isCentered: true,
            onPressed: c.read,
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(() => _Result(parse: c.result.value, onOpen: c.openSheet)),
          const SizedBox(height: AppSpacing.lg),
          const Text('Sample states', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          Text(
            SeedUi.isActive
                ? 'Each opens the confirm sheet on sample data.'
                : 'Run with --dart-define=SEED_UI=1 so these work without a server.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, link) in SeedConnect.targetPresets) ...[
            AppButton.secondary(
              label: label,
              onPressed: () => c.useSample(link),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Text('Invite before sign-in', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Each keeps the link and opens the sign-in screen on it (SEED_UI=1: sample organisations, no server).',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, link) in SeedConnect.invitePresets) ...[
            AppButton.secondary(
              label: label,
              onPressed: () => c.showInvite(link, AppRoutes.authentication),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton.secondary(
            label: 'Welcome screen with the last invite',
            onPressed: c.openWelcome,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Invite code or link sheet',
            onPressed: c.openInviteSheet,
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Invite after sign-in', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Opens the enterprises screen on the link (sample account).',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, link) in SeedConnect.chainPresets) ...[
            AppButton.secondary(
              label: label,
              onPressed: () => c.showInvite(link, AppRoutes.enterprises),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.lg),
          const Text('Install referrer', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'connect_code=CODE[&connect_org=ORG][&connect_branch=NAME]. Nothing touches Play or the server.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: c.referrer,
            label: 'Simulate referrer',
            hint: 'connect_code=7K2M9QWX&connect_branch=Main%20Clinic',
            autocorrect: false,
            onSubmitted: (_) => c.simulateReferrer(),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton.primary(
            label: 'Run the first-start logic',
            isCentered: true,
            onPressed: c.simulateReferrer,
          ),
          Obx(() {
            final text = c.referrerResult.value;
            if (text == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(text, style: AppText.readable),
            );
          }),
          const SizedBox(height: AppSpacing.sm),
          AppButton.secondary(
            label: 'Run the parser test vectors',
            onPressed: c.runVectors,
          ),
          Obx(
            () => c.vectorLines.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      c.vectorLines.join('\n'),
                      style: AppText.readable,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.parse, required this.onOpen});

  final ConnectParse? parse;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = parse;
    if (p == null) return const SizedBox.shrink();
    final value = p.value;
    final lines = value == null
        ? 'Rejected: ${p.rejection?.name}'
        : 'code: ${value.display}\n'
              'org: ${value.org ?? '-'}\n'
              'branch: ${value.branch ?? '-'}\n'
              'sent to the server as: ${value.linkText}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: value == null ? AppColors.primaryTint : AppColors.yesFill,
            borderRadius: AppRadius.mdAll,
          ),
          child: Text(lines, style: AppText.readable),
        ),
        if (value != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Open the confirm sheet',
            onPressed: onOpen,
          ),
        ],
      ],
    );
  }
}
