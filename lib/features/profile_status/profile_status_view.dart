import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/profile/profile.dart';
import '../../data/profile/presence.dart';
import '../../data/profile/status_text.dart';
import 'profile_status_controller.dart';

class ProfileStatusView extends GetView<ProfileStatusController> {
  const ProfileStatusView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppDiscardGuard(
      isDirty: c.isDirty,
      title: ProfileTexts.discardTitle,
      message: ProfileTexts.discardBody,
      discardLabel: ProfileTexts.discard,
      keepLabel: ProfileTexts.keepEditing,
      child: AppScaffold(
        isScrollable: false,
        showOfflineBar: true,
        padding: EdgeInsets.zero,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => AppButton.icon(
                      icon: Icons.arrow_back,
                      semanticLabel: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const Expanded(child: Text('Status', style: AppText.heading)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: _Body(controller: c),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Obx(
                () => AppButton.primary(
                  label: 'Save',
                  isCentered: true,
                  isLoading: c.isSaving.value,
                  onPressed: c.isSaving.value
                      ? null
                      : () async {
                          if (await c.save()) Get.back<void>();
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final ProfileStatusController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Presence', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'The dot next to your name. It stays until you change it.',
          style: AppText.readable.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        Obx(
          () => Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final p in Presence.values)
                _PresenceChip(
                  presence: p,
                  isSelected: c.presence.value == p,
                  onTap: () => c.choose(p),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Status message', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Shows under your name in the chats list.',
          style: AppText.readable.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: c.text,
          builder: (context, value, _) => AppTextField(
            controller: c.text,
            hint: ProfileTexts.statusHint,
            textInputAction: TextInputAction.done,
            inputFormatters: const [TransformFormatter(StatusText.typed)],
            onSubmitted: (_) async {
              if (c.hasChanges && await c.save()) Get.back<void>();
            },
            suffix: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear status',
                    constraints: const BoxConstraints(
                      minWidth: AppSpacing.minTapTarget,
                      minHeight: AppSpacing.minTapTarget,
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: AppColors.muted,
                    ),
                    onPressed: c.clear,
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: c.text,
          builder: (context, value, _) {
            final n = StatusText.length(value.text);
            return Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '$n/${StatusText.maxLength}',
                key: const ValueKey('status-counter'),
                style: AppText.caption.copyWith(
                  color: n >= StatusText.warnFrom
                      ? AppColors.ink
                      : AppColors.muted,
                  fontWeight: n >= StatusText.warnFrom
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            );
          },
        ),
        Obx(() {
          final message = c.error.value;
          if (message == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(message, style: AppText.error),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.lg),
        const Text('Preview', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.xs),
        _Preview(controller: c),
      ],
    );
  }
}

class _PresenceChip extends StatelessWidget {
  const _PresenceChip({
    required this.presence,
    required this.isSelected,
    required this.onTap,
  });

  final Presence presence;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = AppPresenceTones.of(presence);
    return Semantics(
      button: true,
      selected: isSelected,
      label: presence.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isSelected ? tone.tint : AppColors.white,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: isSelected
                    ? AppPresenceTones.dot(presence)
                    : AppColors.line,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PresenceDotView(presence: presence),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      presence.label,
                      style: AppText.readableStrong.copyWith(
                        color: isSelected ? tone.strong : AppColors.ink,
                      ),
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Icon(Icons.check_rounded, size: 16, color: tone.strong),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});

  final ProfileStatusController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Obx(
            () => AppAvatar(
              name: c.name,
              kind: AppAvatarKind.person,
              picture: c.picture,
              presence: AppPresenceDot.online,
              mood: c.presence.value,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.readableStrong,
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: c.text,
                  builder: (context, value, _) {
                    final message = StatusText.toSend(value.text);
                    return Text(
                      message.isEmpty ? ProfileTexts.noStatus : message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.readable.copyWith(
                        color: AppColors.muted,
                        fontStyle: message.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
