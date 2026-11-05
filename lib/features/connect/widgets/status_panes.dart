import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../core/widgets/app_success_animation.dart';
import '../../../data/models/identity_info.dart';
import '../connect_controller.dart';
import '../../../core/widgets/app_loading.dart';

class ResolvingPane extends StatelessWidget {
  const ResolvingPane({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: AppSpacing.stateImage,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppLoading(),
          SizedBox(height: AppSpacing.md),
          Text('Looking up the enterprise…', style: AppText.readable),
        ],
      ),
    );
  }
}

class FailedPane extends StatelessWidget {
  const FailedPane({super.key, required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final kind = c.failure.value;
    final canRetry = kind != ConnectFailure.notFound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AppStateImage(
            kind: switch (kind) {
              ConnectFailure.notFound => AppStateImageKind.noResults,
              ConnectFailure.offline => AppStateImageKind.offline,
              _ => AppStateImageKind.error,
            },
            size: AppSpacing.stateImageSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          c.failureTitle,
          style: AppText.subtitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          c.failureBody,
          style: AppText.readable,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (canRetry)
          AppButton.primary(
            label: 'Try again',
            isCentered: true,
            onPressed: c.retry,
          ),
        if (canRetry) const SizedBox(height: AppSpacing.xs),
        AppButton.secondary(
          label: c.mode.value == ConnectMode.scan ? 'Back to scanner' : 'Back',
          onPressed: c.backToEntry,
        ),
      ],
    );
  }
}

class DonePane extends StatelessWidget {
  const DonePane({super.key, required this.controller, required this.onEnter});

  final ConnectController controller;
  final Future<void> Function(EnterpriseMembership) onEnter;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final name = c.card.value?.name ?? 'the enterprise';
    final isSent = c.outcome.value == ConnectOutcome.requestSent;
    final welcome = c.welcome.value;
    final m = c.membership.value;
    final hasPerson = c.keptPersonLink != null;
    final from = c.awaitingFrom.value;
    final values = {'you': 'You', 'name': name, 'from': from ?? ''};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: isSent
              ? Container(
                  width: AppSpacing.checkBadge,
                  height: AppSpacing.checkBadge,
                  decoration: const BoxDecoration(
                    color: AppColors.accentTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top,
                    size: 28,
                    color: AppColors.accent,
                  ),
                )
              : const AppSuccessAnimation(),
        ),
        const SizedBox(height: AppSpacing.md),
        AppHighlightText(
          isSent ? 'Request sent, waiting for approval' : '{you} joined {name}',
          values: values,
          style: AppText.title,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (isSent || welcome == null)
          AppHighlightText(
            isSent
                ? '${from == null ? '' : 'Waiting for approval from {from}. '}{name} needs to approve your request. It now shows on your list as Waiting for approval. When you open the app again we check, and {you} can enter once it is approved.'
                : '{you} can enter it now.',
            values: values,
            style: AppText.body,
            textAlign: TextAlign.center,
          )
        else
          Text(welcome, style: AppText.body, textAlign: TextAlign.center),
        if (isSent && welcome != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(welcome, style: AppText.readable, textAlign: TextAlign.center),
        ],
        if (hasPerson) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            isSent
                ? 'Once you are in, you can connect with the person whose QR you scanned.'
                : '{you} can connect with the person whose QR you scanned from inside {name}.',
            style: AppText.readable,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (!isSent && m != null && m.isActive) ...[
          AppButton.primary(
            label: 'Enter $name',
            icon: Icons.chevron_right,
            isCentered: true,
            onPressed: () {
              Navigator.of(context).pop();
              onEnter(m);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.text(
            label: 'Not now',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ] else
          AppButton.primary(
            label: 'Done',
            isCentered: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }
}
