import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_highlight_text.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_success_animation.dart';
import '../../core/widgets/app_tag.dart';
import '../../data/models/connect_card.dart';
import '../../data/models/connect_lookup.dart';
import '../enterprises/widgets/enterprise_tile.dart';
import 'connect_target_controller.dart';
import '../../core/widgets/app_loading.dart';

/// The body of the connect sheet: one sheet that moves from the lookup to the
/// question to the result.
class ConnectTargetView extends GetView<ConnectTargetController> {
  const ConnectTargetView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) c.onUserClosed();
      },
      child: AnimatedSize(
        duration: AppDurations.sheetResize,
        curve: AppCurves.inOut,
        alignment: Alignment.topCenter,
        child: Obx(() {
          final step = c.step.value;
          return AnimatedSwitcher(
            duration: AppDurations.fast,
            switchInCurve: AppCurves.out,
            switchOutCurve: AppCurves.easeIn,
            child: KeyedSubtree(
              key: ValueKey(step),
              child: switch (step) {
                ConnectTargetStep.resolving => const _Resolving(),
                ConnectTargetStep.person => _PersonPane(controller: c),
                ConnectTargetStep.organisation => _OrganisationPane(
                  controller: c,
                ),
                ConnectTargetStep.otherOrganisation => _OtherPane(
                  controller: c,
                ),
                ConnectTargetStep.connected => _ResultPane(
                  controller: c,
                  isNew: true,
                ),
                ConnectTargetStep.alreadyAssociates => _ResultPane(
                  controller: c,
                  isNew: false,
                ),
                ConnectTargetStep.failed => _FailedPane(controller: c),
              },
            ),
          );
        }),
      ),
    );
  }
}

class _Resolving extends StatelessWidget {
  const _Resolving();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: AppSpacing.stateImage,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppLoading(),
          SizedBox(height: AppSpacing.md),
          Text('Checking the code…', style: AppText.readable),
        ],
      ),
    );
  }
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({required this.person});

  final ConnectPerson person;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppAvatar(name: person.name, size: AppSpacing.tileSize),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(person.name, style: AppText.subtitle),
              if (person.summary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(person.summary, style: AppText.readable),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonPane extends StatelessWidget {
  const _PersonPane({required this.controller});

  final ConnectTargetController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final person = c.person.value;
    if (person == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PersonHeader(person: person),
        const SizedBox(height: AppSpacing.md),
        AppHighlightText(
          'Connect with {name}?',
          values: {'name': person.name},
          style: AppText.title,
        ),
        const SizedBox(height: AppSpacing.xs),
        const AppHighlightText(
          '{you} will become associates and they will be told.',
          values: {'you': 'You'},
        ),
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: 'Yes, connect',
            isCentered: true,
            isLoading: c.isBusy.value,
            onPressed: c.connect,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(
          label: 'No',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _OrgHeader extends StatelessWidget {
  const _OrgHeader({required this.card});

  final ConnectCard card;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EnterpriseTile(index: 0, isCurrent: false),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.name, style: AppText.subtitle),
              if (card.location.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(card.location, style: AppText.readable),
              ],
              if (card.branch != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppTag(label: card.branch!, icon: Icons.place_outlined),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _OrganisationPane extends StatelessWidget {
  const _OrganisationPane({required this.controller});

  final ConnectTargetController controller;

  @override
  Widget build(BuildContext context) {
    final card = controller.card.value;
    if (card == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OrgHeader(card: card),
        const SizedBox(height: AppSpacing.md),
        AppHighlightText(
          "{you}'re already in {name}.",
          values: {'you': 'You', 'name': card.name},
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton.primary(
          label: 'Done',
          isCentered: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _OtherPane extends StatelessWidget {
  const _OtherPane({required this.controller});

  final ConnectTargetController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final card = c.card.value;
    if (card == null) return const SizedBox.shrink();
    final m = c.membership.value;
    final note = c.otherOrganisationNote;
    final isPerson = c.isConnectAfterSwitch;
    final values = {'name': card.name, 'you': 'You'};
    final title = m == null
        ? 'Join {name}?'
        : isPerson
        ? 'Connect in {name}?'
        : m.isActive
        ? 'Switch to {name}?'
        : '{name}';
    final body =
        note ??
        (m == null
            ? 'This code is for {name}, not the enterprise you are in. Join it first, then connect.'
            : isPerson
            ? 'This person is in {name}. One tap switches you to it and connects you.'
            : 'This code is for {name}, not the enterprise you are in.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OrgHeader(card: card),
        const SizedBox(height: AppSpacing.md),
        AppHighlightText(title, values: values, style: AppText.title),
        const SizedBox(height: AppSpacing.xs),
        AppHighlightText(body, values: values),
        Obx(() {
          final error = c.message.value;
          return error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(error, style: AppText.error),
                );
        }),
        const SizedBox(height: AppSpacing.lg),
        if (m == null)
          AppButton.primary(
            label: 'Join ${card.name}',
            isCentered: true,
            onPressed: () {
              c.joinOrganisation();
              Navigator.of(context).pop();
            },
          )
        else if (m.isActive)
          Obx(
            () => AppButton.primary(
              label: isPerson ? 'Connect' : 'Switch to ${card.name}',
              isCentered: true,
              isLoading: c.isBusy.value,
              onPressed: c.switchOrganisation,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(
          label: m == null || m.isActive ? 'Not now' : 'Got it',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ResultPane extends StatelessWidget {
  const _ResultPane({required this.controller, required this.isNew});

  final ConnectTargetController controller;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final person = c.person.value;
    if (person == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: isNew
              ? const AppSuccessAnimation()
              : Container(
                  width: AppSpacing.checkBadge,
                  height: AppSpacing.checkBadge,
                  decoration: const BoxDecoration(
                    color: AppColors.accentTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.people_outline,
                    size: 28,
                    color: AppColors.accent,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppHighlightText(
          isNew
              ? "{you}'re now connected with {name}"
              : '{you} and {name} are already associates',
          values: {'you': 'You', 'name': person.name},
          style: AppText.title,
          textAlign: TextAlign.center,
        ),
        if (person.role.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            person.role,
            style: AppText.readable,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        AppButton.primary(
          label: 'Open chat',
          icon: Icons.chevron_right,
          isCentered: true,
          onPressed: () {
            Navigator.of(context).pop();
            c.openChat();
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _FailedPane extends StatelessWidget {
  const _FailedPane({required this.controller});

  final ConnectTargetController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final kind = c.failure.value;
    final canRetry =
        kind == ConnectTargetFailure.offline ||
        kind == ConnectTargetFailure.rateLimited ||
        kind == ConnectTargetFailure.other;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AppStateImage(
            kind: switch (kind) {
              ConnectTargetFailure.notFound ||
              ConnectTargetFailure.invalid ||
              ConnectTargetFailure.refused => AppStateImageKind.noResults,
              ConnectTargetFailure.offline => AppStateImageKind.offline,
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
        if (canRetry) ...[
          AppButton.primary(
            label: 'Try again',
            isCentered: true,
            onPressed: c.load,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        AppButton.secondary(
          label: kind == ConnectTargetFailure.offline ? 'Not now' : 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
