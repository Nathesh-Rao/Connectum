import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import '../../enterprises/widgets/enterprise_tile.dart';
import '../connect_controller.dart';
import 'join_steps.dart';

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
          return JoinSteps(card: card, controller: c);
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
