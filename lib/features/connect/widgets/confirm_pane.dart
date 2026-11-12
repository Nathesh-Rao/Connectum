import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_highlight_text.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/models/connect_card.dart';
import '../../../data/models/identity_info.dart';
import '../../enterprises/widgets/enterprise_tile.dart';
import '../connect_controller.dart';

class ConfirmPane extends StatelessWidget {
  const ConfirmPane({
    super.key,
    required this.controller,
    required this.onEnter,
  });

  final ConnectController controller;
  final Future<void> Function(EnterpriseMembership) onEnter;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final card = c.card.value;
    if (card == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(card: card),
        if (card.isFromPersonLink) ...[
          const SizedBox(height: AppSpacing.sm),
          _Note(
            text:
                "This QR belongs to a person. Join {name} first; you can connect with them once you're in.",
            values: {'name': card.name},
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Obx(() {
          final m = c.membership.value;
          if (m != null) {
            return _Member(
              card: card,
              membership: m,
              controller: c,
              onEnter: onEnter,
            );
          }
          return _JoinForm(card: card, controller: c);
        }),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.card});

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

class _Note extends StatelessWidget {
  const _Note({required this.text, this.values = const {}});

  final String text;
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadius.mdAll,
      ),
      child: AppHighlightText(text, values: values),
    );
  }
}

class _Member extends StatelessWidget {
  const _Member({
    required this.card,
    required this.membership,
    required this.controller,
    required this.onEnter,
  });

  final ConnectCard card;
  final EnterpriseMembership membership;
  final ConnectController controller;
  final Future<void> Function(EnterpriseMembership) onEnter;

  @override
  Widget build(BuildContext context) {
    final m = membership;
    final text = m.isActive
        ? "{you}'re already in {name}."
        : m.status == 'pending'
        ? 'Your request to join {name} is waiting for approval. {you} can enter once an administrator approves it.'
        : "Your earlier request to join {name} wasn't approved. Contact the enterprise if you think that's a mistake.";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppHighlightText(
          text,
          values: {'you': 'You', 'name': card.name},
          style: AppText.body,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (m.isActive)
          AppButton.primary(
            label: 'Open ${card.name}',
            icon: Icons.chevron_right,
            isCentered: true,
            onPressed: () {
              Navigator.of(context).pop();
              onEnter(m);
            },
          )
        else
          AppButton.primary(
            label: 'Done',
            isCentered: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(
          label: 'Scan another',
          onPressed: controller.backToEntry,
        ),
      ],
    );
  }
}

class _JoinForm extends StatelessWidget {
  const _JoinForm({required this.card, required this.controller});

  final ConnectCard card;
  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (card.categories.isEmpty)
          const Text(
            "This enterprise isn't open for joining from the app yet.",
            style: AppText.body,
          )
        else ...[
          const Text('Join as', style: AppText.readableStrong),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 156),
            child: SingleChildScrollView(
              child: Obx(
                () => Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final category in card.categories)
                      _CategoryChip(
                        label: category,
                        isSelected: c.selectedCategory.value == category,
                        onTap: () => c.selectCategory(category),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        Obx(() {
          final error = c.joinMessage.value;
          return error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(error, style: AppText.error),
                );
        }),
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: 'Join ${card.name}',
            isCentered: true,
            isLoading: c.isJoining.value,
            onPressed: c.selectedCategory.value == null ? null : c.join,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton.text(label: 'Cancel', onPressed: c.backToEntry),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppCurves.out,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryTint : AppColors.white,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: isSelected ? AppColors.primaryBright : AppColors.inputBorder,
            ),
          ),
          child: Text(
            label,
            style: AppText.readableStrong.copyWith(
              color: isSelected ? AppColors.primaryStrong : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
