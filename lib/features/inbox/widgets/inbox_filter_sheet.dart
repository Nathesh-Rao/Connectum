import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_inbox.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_switch.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/inbox_field_kinds.dart';
import '../inbox_controller.dart';
import '../inbox_filter_controller.dart';
import '../models/inbox_filter.dart';

/// The Inbox filter panel as a popup card that opens from the filter button
/// (`InboxFilterFab.jsx`). Nothing applies until Apply; closing it any other
/// way drops the draft.
class InboxFilterSheet {
  InboxFilterSheet._();

  static Future<void> show(BuildContext context, InboxController inbox) {
    final panel = inbox.newFilterPanel();
    return open(
      context,
      InboxFilterPanel(panel: panel),
    ).whenComplete(panel.onClose);
  }

  /// Opens a filter panel in the popup card (the Approvals panel too).
  static Future<void> open(BuildContext context, Widget panel) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close the filters',
      barrierColor: AppColors.sheetBackdrop,
      transitionDuration: AppDurations.base,
      pageBuilder: (context, _, _) => InboxFilterPopupFrame(child: panel),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: AppCurves.out);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            alignment: Alignment.topRight,
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// The card: a bordered, rounded, raised surface inside the safe area, lifted
/// by the keyboard.
class InboxFilterPopupFrame extends StatelessWidget {
  const InboxFilterPopupFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: AlignmentDirectional.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppInbox.popupMaxWidth,
              ),
              child: Material(
                color: AppColors.white,
                elevation: 16,
                shadowColor: AppColors.sheetBackdrop,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppInbox.popupRadius),
                  side: const BorderSide(color: AppInbox.popupBorder),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel's content: header, the sections, Clear and Apply. Public so a
/// test can draw it without a popup.
class InboxFilterPanel extends StatelessWidget {
  const InboxFilterPanel({super.key, required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(panel: panel),
        const Divider(height: 1, thickness: 1, color: AppColors.line),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Where(panel: panel),
                const SizedBox(height: AppSpacing.sm),
                _People(panel: panel),
                const SizedBox(height: AppSpacing.sm),
                _Details(panel: panel),
                const SizedBox(height: AppSpacing.sm),
                _Advanced(panel: panel),
              ],
            ),
          ),
        ),
        _Footer(panel: panel),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.md,
        end: AppSpacing.xs,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          const InboxFilterDisc(
            icon: Icons.tune_rounded,
            tone: AppTones.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Obx(() {
              final n = panel.count;
              return Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  const Text(
                    InboxFilterController.title,
                    style: AppText.subtitle,
                  ),
                  if (n > 0)
                    DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs / 2,
                        ),
                        child: Text(
                          '$n set',
                          style: AppText.caption.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
          Semantics(
            button: true,
            label: 'Close the filters',
            excludeSemantics: true,
            child: Tooltip(
              message: 'Close the filters',
              excludeFromSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox(
                  width: AppInbox.hit,
                  height: AppInbox.hit,
                  child: Icon(
                    Icons.close_rounded,
                    size: AppInbox.discIcon,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round tinted disc with an icon: the mark of a section or a line.
class InboxFilterDisc extends StatelessWidget {
  const InboxFilterDisc({super.key, required this.icon, required this.tone});

  final IconData icon;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    const d = AppInbox.sectionIcon;
    return DecoratedBox(
      decoration: BoxDecoration(color: tone.tint, shape: BoxShape.circle),
      child: SizedBox(
        width: d,
        height: d,
        child: Icon(icon, size: d * 0.56, color: tone.strong),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                label: InboxFilterController.clearLabel,
                onPressed: () {
                  panel.clear();
                  Navigator.of(context).pop();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton.primary(
                label: InboxFilterController.applyLabel,
                isCentered: true,
                onPressed: () {
                  panel.apply();
                  Navigator.of(context).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section card: its mark, its title, how many lines of it are set, then
/// its lines.
class InboxFilterSection extends StatelessWidget {
  const InboxFilterSection({
    super.key,
    required this.title,
    required this.icon,
    required this.tone,
    required this.count,
    required this.children,
  });

  final String title;
  final IconData icon;
  final AppTone tone;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return InboxFilterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                InboxFilterDisc(icon: icon, tone: tone),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(title, style: AppText.subtitle)),
                if (count > 0) ...[
                  const SizedBox(width: AppSpacing.xs),
                  DecoratedBox(
                    key: ValueKey('filter-count-$title'),
                    decoration: BoxDecoration(
                      color: tone.tintStrong,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs / 2,
                      ),
                      child: Text(
                        '$count',
                        style: AppText.caption.copyWith(
                          color: tone.strong,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final c in children) ...[
            const SizedBox(height: AppSpacing.sm),
            c,
          ],
        ],
      ),
    );
  }
}

/// A rounded, bordered card the lines of a section sit on.
class InboxFilterCard extends StatelessWidget {
  const InboxFilterCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppInbox.cardFill,
        borderRadius: BorderRadius.circular(AppInbox.cardRadius),
        border: Border.all(color: AppInbox.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: child,
      ),
    );
  }
}

class _Where extends StatelessWidget {
  const _Where({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = panel.draft.value;
      return InboxFilterSection(
        title: 'Where and what',
        icon: Icons.travel_explore_rounded,
        tone: AppInbox.whereTone,
        count: d.wheres.length + d.forms.length,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const InboxFilterLineLabel(
                icon: Icons.manage_search_rounded,
                label: InboxFilterController.searchInLabel,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final c in panel.searchInChoices)
                    InboxFilterChip(
                      label: c.label,
                      isSelected: d.wheres.contains(c.id),
                      onTap: () => panel.setWheres(
                        d.wheres.contains(c.id)
                            ? [
                                for (final w in d.wheres)
                                  if (w != c.id) w,
                              ]
                            : [...d.wheres, c.id],
                      ),
                    ),
                ],
              ),
            ],
          ),
          _PickLine(
            icon: Icons.dataset_outlined,
            label: InboxFilterController.formLabel,
            panel: panel,
            choices: () => panel.formChoices,
            extra: () => panel.allFormChoices,
            selected: () => panel.draft.value.forms,
            onChanged: panel.setForms,
            emptyText: () => panel.formsEmptyText,
            isEmptyShownAsText: true,
          ),
        ],
      );
    });
  }
}

const _peopleIcons = {
  'createdBy': Icons.edit_note_rounded,
  'sentBy': Icons.outbox_rounded,
  'sentTo': Icons.move_to_inbox_rounded,
  'taggedTo': Icons.alternate_email_rounded,
};

class _People extends StatelessWidget {
  const _People({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = panel.draft.value;
      return InboxFilterSection(
        title: 'People',
        icon: Icons.groups_rounded,
        tone: AppInbox.peopleTone,
        count: [
          for (final k in inboxPeopleKeys) d.peopleOf(k).length,
        ].fold(0, (a, b) => a + b),
        children: [
          for (final key in inboxPeopleKeys)
            _PickLine(
              icon: _peopleIcons[key] ?? Icons.person_outline_rounded,
              label: InboxFilterController.labels[key] ?? key,
              panel: panel,
              choices: () => panel.peopleChoices(key),
              selected: () => panel.draft.value.peopleOf(key),
              onChanged: (list) => panel.setPeople(key, list),
              emptyText: () => InboxFilterController.nobodyText,
            ),
        ],
      );
    });
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = panel.draft.value;
      final isSortSet = d.status.isNotEmpty || d.sort != InboxSort.latest;
      return InboxFilterSection(
        title: 'Date and order',
        icon: Icons.event_note_rounded,
        tone: AppInbox.detailsTone,
        count:
            (d.from.isNotEmpty ? 1 : 0) +
            (d.to.isNotEmpty ? 1 : 0) +
            (isSortSet ? 1 : 0),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const InboxFilterLineLabel(
                icon: Icons.event_rounded,
                label: InboxFilterController.dateLabel,
              ),
              const SizedBox(height: AppSpacing.xs),
              LayoutBuilder(
                builder: (context, box) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final from = InboxFilterDateField(
                    label: '${InboxFilterController.dateLabel}: from',
                    caption: 'From date',
                    value: d.from,
                    first: DateTime(2000),
                    last: _dayOf(d.to) ?? DateTime(2100),
                    onPicked: panel.setFrom,
                  );
                  final to = InboxFilterDateField(
                    label: '${InboxFilterController.dateLabel}: to',
                    caption: 'To date',
                    value: d.to,
                    first: _dayOf(d.from) ?? DateTime(2000),
                    last: DateTime(2100),
                    onPicked: panel.setTo,
                  );
                  if (box.maxWidth < 300 * scale) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        from,
                        const SizedBox(height: AppSpacing.xs),
                        to,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: from),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: to),
                    ],
                  );
                },
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const InboxFilterLineLabel(
                icon: Icons.swap_vert_rounded,
                label: InboxFilterController.sortLabel,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (id, label) in InboxSort.choices)
                    InboxFilterChip(
                      label: label,
                      isSelected: d.sortChoice == id,
                      onTap: () => panel.setSortChoice(id),
                    ),
                ],
              ),
            ],
          ),
        ],
      );
    });
  }

  static DateTime? _dayOf(String s) => DateTime.tryParse(s);
}

/// A line with many possible choices (forms, people): the picked ones as
/// removable chips and an Add chip that opens the searchable list.
class _PickLine extends StatelessWidget {
  const _PickLine({
    required this.icon,
    required this.label,
    required this.panel,
    required this.choices,
    required this.selected,
    required this.onChanged,
    required this.emptyText,
    this.extra,
    this.isEmptyShownAsText = false,
  });

  final IconData icon;
  final String label;
  final InboxFilterController panel;
  final List<InboxChoice> Function() choices;
  final List<InboxChoice> Function()? extra;
  final List<String> Function() selected;
  final ValueChanged<List<String>> onChanged;
  final String Function() emptyText;

  /// With nothing to pick, the line shows [emptyText] instead of Add.
  final bool isEmptyShownAsText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InboxFilterLineLabel(icon: icon, label: label),
        const SizedBox(height: AppSpacing.xs),
        Obx(() {
          final all = choices();
          final picked = selected();
          if (isEmptyShownAsText && all.isEmpty && picked.isEmpty) {
            return Text(
              emptyText(),
              style: AppText.body.copyWith(color: AppColors.muted),
            );
          }
          final known = [...all, ...?extra?.call()];
          return Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final id in picked)
                InboxFilterRemovableChip(
                  key: ValueKey('filter-remove-$label-$id'),
                  label: panel.summaryOf([id], known, ''),
                  onTap: () => onChanged([
                    for (final p in picked)
                      if (p != id) p,
                  ]),
                ),
              InboxFilterAddChip(
                key: ValueKey('filter-add-$label'),
                label: label,
                onTap: () => InboxFilterMultiSheet.show(
                  context,
                  title: label,
                  choices: choices,
                  selected: selected,
                  onChanged: onChanged,
                  emptyText: emptyText,
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

class InboxFilterRemovableChip extends StatelessWidget {
  const InboxFilterRemovableChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove $label',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppInbox.removableFill,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: AppInbox.popupBorder),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.sm,
                end: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: AppText.readableStrong.copyWith(
                        color: AppInbox.removableInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppInbox.removableInk,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InboxFilterAddChip extends StatelessWidget {
  const InboxFilterAddChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add $label',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppInbox.chipFill,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: AppInbox.chipBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Add',
                    style: AppText.readableStrong.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Advanced extends StatelessWidget {
  const _Advanced({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return InboxFilterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(() {
            final isOpen = panel.isAdvanced.value;
            final n = panel.advancedCount;
            return Semantics(
              button: true,
              expanded: isOpen,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: panel.toggleAdvanced,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTapTarget,
                  ),
                  child: Row(
                    children: [
                      const InboxFilterDisc(
                        icon: Icons.account_tree_outlined,
                        tone: AppInbox.advancedTone,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Advanced filter${n > 0 ? '  $n' : ''}',
                          style: AppText.subtitle,
                        ),
                      ),
                      AnimatedRotation(
                        turns: isOpen ? 0.5 : 0,
                        duration: AppDurations.fast,
                        child: const Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          Obx(
            () => panel.isAdvanced.value
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: _Blocks(panel: panel),
                  )
                : const SizedBox.shrink(),
          ),
          Obx(
            () => panel.isAdvanced.value && panel.isApprovalOffered
                ? _ApprovalTicks(panel: panel)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Advanced > Approval: the answers of the approval flow of a form named in
/// a block, shown only when one is named that has such a flow.
class _ApprovalTicks extends StatelessWidget {
  const _ApprovalTicks({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            InboxFilterController.approvalLabel,
            style: AppText.fieldLabel,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Obx(() {
            final picked = panel.draft.value.approvalPick;
            return Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final id in InboxApprovalAnswer.all)
                  InboxFilterChip(
                    label: InboxApprovalAnswer.labels[id] ?? id,
                    isSelected: picked.contains(id),
                    onTap: () => panel.toggleApprovalPick(id),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _Blocks extends StatelessWidget {
  const _Blocks({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final blocks = panel.draft.value.blocks;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _BlockCard(panel: panel, index: i, block: blocks[i]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AppButton.text(
                label: 'Add more data',
                tone: AppTextButtonTone.accent,
                leadingIcon: Icons.add,
                onPressed: panel.canAddBlock ? panel.addBlock : null,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.panel,
    required this.index,
    required this.block,
  });

  final InboxFilterController panel;
  final int index;
  final InboxBlock block;

  @override
  Widget build(BuildContext context) {
    final forms = panel.allFormChoices;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Data ${index + 1}', style: AppText.fieldLabel),
                ),
                AppButton.icon(
                  icon: Icons.delete_outline,
                  semanticLabel: 'Remove data ${index + 1}',
                  onPressed: () => panel.removeBlock(block.id),
                ),
              ],
            ),
            InboxFilterSelectLine(
              icon: Icons.dataset_outlined,
              label: InboxFilterController.formLabel,
              summary: panel.summaryOf(block.forms, forms, 'Any data'),
              hasValue: block.forms.isNotEmpty,
              onTap: () => InboxFilterMultiSheet.show(
                context,
                title: InboxFilterController.formLabel,
                choices: () => panel.allFormChoices,
                selected: () => _now().forms,
                onChanged: (l) => panel.setBlockForms(block.id, l),
                emptyText: () => InboxFilterController.noFormsYetText,
              ),
            ),
            for (final key in const ['createdBy', 'sentBy', 'sentTo']) ...[
              const SizedBox(height: AppSpacing.sm),
              InboxFilterSelectLine(
                icon: _peopleIcons[key] ?? Icons.person_outline_rounded,
                label: InboxFilterController.labels[key] ?? key,
                summary: panel.summaryOf(
                  _of(block, key),
                  panel.blockPeopleChoices(key),
                  InboxFilterController.anybody,
                ),
                hasValue: _of(block, key).isNotEmpty,
                onTap: () => InboxFilterMultiSheet.show(
                  context,
                  title: InboxFilterController.labels[key] ?? key,
                  choices: () => panel.blockPeopleChoices(key),
                  selected: () => _of(_now(), key),
                  onChanged: (l) => panel.changeBlock(
                    block.id,
                    (b) => switch (key) {
                      'createdBy' => b.copyWith(createdBy: l),
                      'sentBy' => b.copyWith(sentBy: l),
                      _ => b.copyWith(sentTo: l),
                    },
                  ),
                  emptyText: () => InboxFilterController.nobodyText,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _Conditions(panel: panel, blockId: block.id, fallback: block),
          ],
        ),
      ),
    );
  }

  InboxBlock _now() => panel.draft.value.blocks.firstWhere(
    (b) => b.id == block.id,
    orElse: () => block,
  );

  static List<String> _of(InboxBlock b, String key) => switch (key) {
    'createdBy' => b.createdBy,
    'sentBy' => b.sentBy,
    _ => b.sentTo,
  };
}

/// A line of the panel: its label over a box that shows what is chosen and
/// opens the list.
class InboxFilterSelectLine extends StatelessWidget {
  const InboxFilterSelectLine({
    super.key,
    required this.icon,
    required this.label,
    required this.summary,
    required this.hasValue,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String summary;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InboxFilterLineLabel(icon: icon, label: label),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          button: true,
          label: '$label, $summary',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: InboxFilterBox(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(
                        color: hasValue ? AppColors.ink : AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.unfold_more_rounded,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A line's label with its own small icon.
class InboxFilterLineLabel extends StatelessWidget {
  const InboxFilterLineLabel({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.muted),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(label, style: AppText.fieldLabel)),
      ],
    );
  }
}

class InboxFilterBox extends StatelessWidget {
  const InboxFilterBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.inputBorder),
      ),
      alignment: AlignmentDirectional.centerStart,
      child: child,
    );
  }
}

/// One compact date field: a caption over the day, a clear button when set.
class InboxFilterDateField extends StatelessWidget {
  const InboxFilterDateField({
    super.key,
    required this.label,
    required this.caption,
    required this.value,
    required this.first,
    required this.last,
    required this.onPicked,
  });

  final String label;
  final String caption;
  final String value;
  final DateTime first;
  final DateTime last;
  final ValueChanged<String> onPicked;

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final has = value.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: has ? '$label, $value' : label,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final start = DateTime.tryParse(value) ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: start.isBefore(first)
                        ? first
                        : start.isAfter(last)
                        ? last
                        : start,
                    firstDate: first,
                    lastDate: last,
                  );
                  if (picked != null) onPicked(iso(picked));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(caption, style: AppText.caption),
                            Text(
                              has ? value : 'Any day',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body.copyWith(
                                color: has ? AppColors.ink : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (has)
            AppButton.icon(
              icon: Icons.close,
              semanticLabel: 'Clear $label',
              onPressed: () => onPicked(''),
            ),
        ],
      ),
    );
  }
}

class InboxFilterDateLine extends StatelessWidget {
  const InboxFilterDateLine({
    super.key,
    required this.label,
    required this.value,
    required this.first,
    required this.last,
    required this.onPicked,
    this.emptyText = 'Any day',
  });

  final String emptyText;
  final String label;
  final String value;
  final DateTime first;
  final DateTime last;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final has = value.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InboxFilterLineLabel(icon: Icons.event_rounded, label: label),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: has ? '$label, $value' : label,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final start = DateTime.tryParse(value) ?? DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: start.isBefore(first)
                          ? first
                          : start.isAfter(last)
                          ? last
                          : start,
                      firstDate: first,
                      lastDate: last,
                    );
                    if (picked != null) {
                      onPicked(InboxFilterDateField.iso(picked));
                    }
                  },
                  child: InboxFilterBox(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            has ? value : emptyText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(
                              color: has ? AppColors.ink : AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (has)
              AppButton.icon(
                icon: Icons.close,
                semanticLabel: 'Clear $label',
                onPressed: () => onPicked(''),
              ),
          ],
        ),
      ],
    );
  }
}

class InboxFilterChip extends StatelessWidget {
  const InboxFilterChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isDimmed = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// Looks muted (nothing behind it) but still takes a tap.
  final bool isDimmed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppCurves.out,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: isSelected ? AppInbox.chipSelectedFill : AppInbox.chipFill,
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: isSelected
                    ? AppInbox.chipSelectedFill
                    : AppInbox.chipBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppInbox.chipSelectedInk,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: AppText.readableStrong.copyWith(
                      color: isSelected
                          ? AppInbox.chipSelectedInk
                          : isDimmed
                          ? AppColors.muted
                          : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A searchable list with several choices. [choices] and [selected] are read
/// inside an `Obx`, so the list follows the panel (the facet answer can land
/// while it is open).
class InboxFilterMultiSheet extends StatefulWidget {
  const InboxFilterMultiSheet({
    super.key,
    required this.title,
    required this.choices,
    required this.selected,
    required this.onChanged,
    required this.emptyText,
    required this.isSearchable,
  });

  final String title;
  final List<InboxChoice> Function() choices;
  final List<String> Function() selected;
  final ValueChanged<List<String>> onChanged;
  final String Function() emptyText;
  final bool isSearchable;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<InboxChoice> Function() choices,
    required List<String> Function() selected,
    required ValueChanged<List<String>> onChanged,
    required String Function() emptyText,
    bool isSearchable = true,
  }) {
    return AppBottomSheet.showPinned<void>(
      context,
      child: InboxFilterMultiSheet(
        title: title,
        choices: choices,
        selected: selected,
        onChanged: onChanged,
        emptyText: emptyText,
        isSearchable: isSearchable,
      ),
    );
  }

  @override
  State<InboxFilterMultiSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<InboxFilterMultiSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    final now = [...widget.selected()];
    now.contains(id) ? now.remove(id) : now.add(id);
    widget.onChanged(now);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sheetPaddingX,
            AppSpacing.xs,
            AppSpacing.sheetPaddingX,
            AppSpacing.xs,
          ),
          child: Text(widget.title, style: AppText.subtitle),
        ),
        if (widget.isSearchable)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sheetPaddingX,
            ),
            child: AppSearchField(
              hint: 'Search',
              controller: _search,
              onChanged: (_) {},
            ),
          ),
        Flexible(
          child: Obx(() {
            final all = widget.choices();
            final picked = widget.selected();
            return ValueListenableBuilder<TextEditingValue>(
              valueListenable: _search,
              builder: (context, value, _) {
                final q = value.text.trim().toLowerCase();
                final shown = [
                  for (final c in all)
                    if (q.isEmpty || c.label.toLowerCase().contains(q)) c,
                ];
                if (shown.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.sheetPaddingX),
                    child: Text(
                      all.isEmpty ? widget.emptyText() : 'No match.',
                      style: AppText.body.copyWith(color: AppColors.muted),
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sheetPaddingX,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final c = shown[i];
                    final isOn = picked.contains(c.id);
                    return Semantics(
                      button: true,
                      checked: isOn,
                      label: c.label,
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _toggle(c.id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: AppSpacing.minTapTarget,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isOn
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                color: isOn
                                    ? AppColors.primary
                                    : AppColors.muted,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.xs,
                                  ),
                                  child: Text(c.label, style: AppText.body),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          }),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sheetPaddingX,
            AppSpacing.sm,
            AppSpacing.sheetPaddingX,
            AppSpacing.md + MediaQuery.paddingOf(context).bottom,
          ),
          child: AppButton.primary(
            label: 'Done',
            isCentered: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }
}

// ---- conditions ---------------------------------------------------------------

/// The conditions of one block (`FilterBlocks.jsx`): only for a block that
/// names exactly one form, whose fields come from the form definition.
class _Conditions extends StatelessWidget {
  const _Conditions({
    required this.panel,
    required this.blockId,
    required this.fallback,
  });

  final InboxFilterController panel;
  final String blockId;
  final InboxBlock fallback;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final block = panel.draft.value.blocks.firstWhere(
        (b) => b.id == blockId,
        orElse: () => fallback,
      );
      final state = panel.kindsState.value;
      if (block.forms.isEmpty) {
        return const InboxFilterNote(
          InboxFilterController.conditionsNeedOneFormText,
        );
      }
      if (!panel.hasOneForm(block)) {
        return const InboxFilterNote(
          InboxFilterController.conditionsManyFormsText,
        );
      }
      if (state == InboxKindsState.failed) {
        return const InboxFilterNote(
          InboxFilterController.conditionsUnavailableText,
        );
      }
      if (state != InboxKindsState.ready) {
        return const InboxFilterNote(
          InboxFilterController.conditionsLoadingText,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < block.conditions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ConditionCard(
                panel: panel,
                block: block,
                condition: block.conditions[i],
                index: i,
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton.text(
              label: 'Add a condition',
              tone: AppTextButtonTone.accent,
              onPressed: panel.canAddCondition(block)
                  ? () => panel.addCondition(block.id)
                  : null,
            ),
          ),
        ],
      );
    });
  }
}

class InboxFilterNote extends StatelessWidget {
  const InboxFilterNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppText.caption.copyWith(color: AppColors.muted));
}

class _ConditionCard extends StatelessWidget {
  const _ConditionCard({
    required this.panel,
    required this.block,
    required this.condition,
    required this.index,
  });

  final InboxFilterController panel;
  final InboxBlock block;
  final InboxCondition condition;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = condition;
    final fields = panel.fieldChoices(block);
    final field = fields.where((f) => f.id == c.field).firstOrNull;
    final ops = panel.operatorChoices(block, c);
    final op = ops.where((o) => o.id == c.op).firstOrNull;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.controlAll,
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: index == 0
                      ? const Text('Where', style: AppText.fieldLabel)
                      : Obx(() {
                          final join = _now().join;
                          return Wrap(
                            spacing: AppSpacing.xs,
                            children: [
                              for (final (id, label) in const [
                                ('and', 'And'),
                                ('or', 'Or'),
                              ])
                                InboxFilterChip(
                                  label: label,
                                  isSelected: join == id,
                                  onTap: () => panel.setConditionJoin(
                                    block.id,
                                    c.id,
                                    id,
                                  ),
                                ),
                            ],
                          );
                        }),
                ),
                AppButton.icon(
                  icon: Icons.close,
                  semanticLabel: 'Remove condition ${index + 1}',
                  onPressed: () => panel.removeCondition(block.id, c.id),
                ),
              ],
            ),
            InboxFilterSelectLine(
              icon: Icons.list_alt_rounded,
              label: 'Field',
              summary: field?.label ?? 'Choose a field',
              hasValue: field != null,
              onTap: () => InboxFilterSingleSheet.show(
                context,
                title: 'Field',
                choices: () => panel.fieldChoices(block),
                selected: () => _now().field,
                onPicked: (id) => panel.setConditionField(block.id, c.id, id),
              ),
            ),
            if (c.field.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              InboxFilterSelectLine(
                icon: Icons.compare_arrows_rounded,
                label: 'Operator',
                summary: op?.label ?? 'Choose',
                hasValue: op != null,
                onTap: () => InboxFilterSingleSheet.show(
                  context,
                  title: 'Operator',
                  choices: () => panel.operatorChoices(block, _now()),
                  selected: () => _now().op,
                  onPicked: (id) => panel.setConditionOp(block.id, c.id, id),
                  isSearchable: false,
                ),
              ),
              if (InboxOps.needsValue(c.op))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: _ConditionValues(
                    panel: panel,
                    blockId: block.id,
                    condition: c,
                    kind: panel.kindOfCondition(block, c),
                    read: _now,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  InboxCondition _now() =>
      panel.draft.value.blocks
          .where((b) => b.id == block.id)
          .expand((b) => b.conditions)
          .where((x) => x.id == condition.id)
          .firstOrNull ??
      condition;
}

/// The box a condition's value is given in, by the kind of the field: a
/// number, a day, Yes / No, or text; between has two.
class _ConditionValues extends StatelessWidget {
  const _ConditionValues({
    required this.panel,
    required this.blockId,
    required this.condition,
    required this.kind,
    required this.read,
  });

  final InboxFilterController panel;
  final String blockId;
  final InboxCondition condition;
  final String kind;
  final InboxCondition Function() read;

  @override
  Widget build(BuildContext context) {
    final c = condition;
    if (kind == 'bool') {
      return Obx(() {
        final isYes = read().value == 'true';
        return Row(
          children: [
            const Expanded(child: Text('Value', style: AppText.fieldLabel)),
            Text(isYes ? 'Yes' : 'No', style: AppText.body),
            const SizedBox(width: AppSpacing.xs),
            AppSwitch(
              value: isYes,
              onChanged: (v) => panel.setConditionValue(
                blockId,
                c.id,
                value: v ? 'true' : 'false',
              ),
            ),
          ],
        );
      });
    }
    final isBetween = c.op == 'between';
    Widget one(String label, bool isSecond) {
      final key = '${c.id}|${c.field}|${isSecond ? 2 : 1}';
      void set(String v) => isSecond
          ? panel.setConditionValue(blockId, c.id, value2: v)
          : panel.setConditionValue(blockId, c.id, value: v);
      if (kind == 'date') {
        return Obx(() {
          final now = read();
          final text = isSecond ? now.value2 : now.value;
          return InboxFilterDateLine(
            label: label,
            value: text,
            first: DateTime(1900),
            last: DateTime(2100),
            onPicked: set,
            emptyText: 'Choose a day',
          );
        });
      }
      return InboxFilterValueField(
        key: ValueKey(key),
        label: label,
        isNumber: kind == 'number',
        initial: isSecond ? c.value2 : c.value,
        onChanged: set,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        one(isBetween ? 'From' : 'Value', false),
        if (isBetween) ...[
          const SizedBox(height: AppSpacing.sm),
          one('To', true),
        ],
      ],
    );
  }
}

/// A typed value: its own text controller, started from the condition and
/// reset when the field changes (the key holds the condition and field).
class InboxFilterValueField extends StatefulWidget {
  const InboxFilterValueField({
    super.key,
    required this.label,
    required this.isNumber,
    required this.initial,
    required this.onChanged,
  });

  final String label;
  final bool isNumber;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<InboxFilterValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<InboxFilterValueField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      controller: _controller,
      keyboardType: widget.isNumber
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      inputFormatters: [
        if (widget.isNumber)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        LengthLimitingTextInputFormatter(InboxFilterLimits.maxNameChars),
      ],
      onChanged: widget.onChanged,
    );
  }
}

/// A list where one choice is picked; the sheet closes on the tap.
class InboxFilterSingleSheet extends StatefulWidget {
  const InboxFilterSingleSheet({
    super.key,
    required this.title,
    required this.choices,
    required this.selected,
    required this.onPicked,
    required this.isSearchable,
  });

  final String title;
  final List<InboxChoice> Function() choices;
  final String Function() selected;
  final ValueChanged<String> onPicked;
  final bool isSearchable;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<InboxChoice> Function() choices,
    required String Function() selected,
    required ValueChanged<String> onPicked,
    bool isSearchable = true,
  }) {
    return AppBottomSheet.showPinned<void>(
      context,
      child: InboxFilterSingleSheet(
        title: title,
        choices: choices,
        selected: selected,
        onPicked: onPicked,
        isSearchable: isSearchable,
      ),
    );
  }

  @override
  State<InboxFilterSingleSheet> createState() => _SingleSelectSheetState();
}

class _SingleSelectSheetState extends State<InboxFilterSingleSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.choices();
    final picked = widget.selected();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sheetPaddingX,
            AppSpacing.xs,
            AppSpacing.sheetPaddingX,
            AppSpacing.xs,
          ),
          child: Text(widget.title, style: AppText.subtitle),
        ),
        if (widget.isSearchable && all.length > 8)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sheetPaddingX,
            ),
            child: AppSearchField(
              hint: 'Search',
              controller: _search,
              onChanged: (_) {},
            ),
          ),
        Flexible(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _search,
            builder: (context, value, _) {
              final q = value.text.trim().toLowerCase();
              final shown = [
                for (final c in all)
                  if (q.isEmpty || c.label.toLowerCase().contains(q)) c,
              ];
              if (shown.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.sheetPaddingX),
                  child: Text(
                    'No match.',
                    style: AppText.body.copyWith(color: AppColors.muted),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.sheetPaddingX,
                  0,
                  AppSpacing.sheetPaddingX,
                  AppSpacing.md + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final c = shown[i];
                  final isOn = c.id == picked;
                  return Semantics(
                    button: true,
                    selected: isOn,
                    label: c.label,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        widget.onPicked(c.id);
                        Navigator.of(context).pop();
                      },
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppSpacing.minTapTarget,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isOn
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: isOn ? AppColors.primary : AppColors.muted,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.xs,
                                ),
                                child: Text(c.label, style: AppText.body),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
