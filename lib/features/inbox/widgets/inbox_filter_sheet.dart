import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
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

/// The Inbox filter panel as a bottom sheet (`InboxFilterFab.jsx`). Nothing
/// applies until Apply; closing the sheet any other way drops the draft.
class InboxFilterSheet {
  InboxFilterSheet._();

  static Future<void> show(BuildContext context, InboxController inbox) {
    final panel = inbox.newFilterPanel();
    return AppBottomSheet.showPinned<void>(
      context,
      maxHeightFraction: 0.92,
      child: InboxFilterPanel(panel: panel),
    ).whenComplete(panel.onClose);
  }
}

/// The panel's content: header, the lines, Clear and Apply. Public so a test
/// can draw it without a sheet.
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
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sheetPaddingX,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Where(panel: panel),
                _People(panel: panel),
                _Details(panel: panel),
                _Advanced(panel: panel),
                const SizedBox(height: AppSpacing.md),
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
        start: AppSpacing.sheetPaddingX,
        end: AppSpacing.xxs,
        top: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Obx(() {
              final n = panel.count;
              return Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: InboxFilterController.title),
                    if (n > 0)
                      TextSpan(text: '  $n set', style: AppText.caption),
                  ],
                ),
                style: AppText.subtitle,
              );
            }),
          ),
          AppButton.icon(
            icon: Icons.close,
            semanticLabel: 'Close the filters',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sheetPaddingX,
        AppSpacing.sm,
        AppSpacing.sheetPaddingX,
        AppSpacing.md + bottom,
      ),
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
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title.toUpperCase(), style: AppText.label),
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

class _Where extends StatelessWidget {
  const _Where({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Where',
      children: [
        Obx(() {
          final choices = panel.searchInChoices;
          final picked = panel.draft.value.wheres;
          return _SelectLine(
            label: InboxFilterController.searchInLabel,
            summary: panel.summaryOf(
              picked,
              choices,
              InboxFilterController.searchInHint,
            ),
            hasValue: picked.isNotEmpty,
            onTap: () => _MultiSelectSheet.show(
              context,
              title: InboxFilterController.searchInLabel,
              choices: () => panel.searchInChoices,
              selected: () => panel.draft.value.wheres,
              onChanged: panel.setWheres,
              emptyText: () => InboxFilterController.searchInHint,
              isSearchable: false,
            ),
          );
        }),
        Obx(() {
          final choices = panel.formChoices;
          final picked = panel.draft.value.forms;
          return _SelectLine(
            label: InboxFilterController.formLabel,
            summary: panel.summaryOf(
              picked,
              choices,
              choices.isEmpty
                  ? panel.formsEmptyText
                  : InboxFilterController.formLabel,
            ),
            hasValue: picked.isNotEmpty,
            onTap: () => _MultiSelectSheet.show(
              context,
              title: InboxFilterController.formLabel,
              choices: () => panel.formChoices,
              selected: () => panel.draft.value.forms,
              onChanged: panel.setForms,
              emptyText: () => panel.formsEmptyText,
            ),
          );
        }),
      ],
    );
  }
}

class _People extends StatelessWidget {
  const _People({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'People',
      children: [
        for (final key in inboxPeopleKeys)
          Obx(() {
            final label = InboxFilterController.labels[key] ?? key;
            final choices = panel.peopleChoices(key);
            final picked = panel.draft.value.peopleOf(key);
            return _SelectLine(
              label: label,
              summary: panel.summaryOf(
                picked,
                choices,
                InboxFilterController.anybody,
              ),
              hasValue: picked.isNotEmpty,
              onTap: () => _MultiSelectSheet.show(
                context,
                title: label,
                choices: () => panel.peopleChoices(key),
                selected: () => panel.draft.value.peopleOf(key),
                onChanged: (list) => panel.setPeople(key, list),
                emptyText: () => InboxFilterController.nobodyText,
              ),
            );
          }),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Details',
      children: [
        Obx(
          () => _DateLine(
            label: '${InboxFilterController.dateLabel}: from',
            value: panel.draft.value.from,
            first: DateTime(2000),
            last: _dayOf(panel.draft.value.to) ?? DateTime(2100),
            onPicked: panel.setFrom,
          ),
        ),
        Obx(
          () => _DateLine(
            label: '${InboxFilterController.dateLabel}: to',
            value: panel.draft.value.to,
            first: _dayOf(panel.draft.value.from) ?? DateTime(2000),
            last: DateTime(2100),
            onPicked: panel.setTo,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              InboxFilterController.sortLabel,
              style: AppText.fieldLabel,
            ),
            const SizedBox(height: AppSpacing.xs),
            Obx(
              () => Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (id, label) in InboxSort.choices)
                    _Chip(
                      label: label,
                      isSelected: panel.draft.value.sortChoice == id,
                      onTap: () => panel.setSortChoice(id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static DateTime? _dayOf(String s) => DateTime.tryParse(s);
}

class _Advanced extends StatelessWidget {
  const _Advanced({required this.panel});

  final InboxFilterController panel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
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
                      Icon(
                        isOpen ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          'Advanced filter${n > 0 ? '  $n' : ''}',
                          style: AppText.fieldLabel,
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
                ? _Blocks(panel: panel)
                : const SizedBox.shrink(),
          ),
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
            alignment: Alignment.centerLeft,
            child: AppButton.text(
              label: 'Add more data',
              tone: AppTextButtonTone.accent,
              leadingIcon: Icons.add,
              onPressed: panel.canAddBlock ? panel.addBlock : null,
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
            _SelectLine(
              label: InboxFilterController.formLabel,
              summary: panel.summaryOf(block.forms, forms, 'Any data'),
              hasValue: block.forms.isNotEmpty,
              onTap: () => _MultiSelectSheet.show(
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
              _SelectLine(
                label: InboxFilterController.labels[key] ?? key,
                summary: panel.summaryOf(
                  _of(block, key),
                  panel.blockPeopleChoices(key),
                  InboxFilterController.anybody,
                ),
                hasValue: _of(block, key).isNotEmpty,
                onTap: () => _MultiSelectSheet.show(
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
class _SelectLine extends StatelessWidget {
  const _SelectLine({
    required this.label,
    required this.summary,
    required this.hasValue,
    required this.onTap,
  });

  final String label;
  final String summary;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.fieldLabel),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          button: true,
          label: '$label, $summary',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: _Box(
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
                    Icons.expand_more,
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

class _Box extends StatelessWidget {
  const _Box({required this.child});

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
        borderRadius: AppRadius.controlAll,
        border: Border.all(color: AppColors.inputBorder),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class _DateLine extends StatelessWidget {
  const _DateLine({
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

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final has = value.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.fieldLabel),
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
                    if (picked != null) onPicked(iso(picked));
                  },
                  child: _Box(
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

class _Chip extends StatelessWidget {
  const _Chip({
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryTint : AppColors.white,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: isSelected
                    ? AppColors.primaryBorder
                    : AppColors.inputBorder,
              ),
            ),
            child: Text(
              label,
              style: AppText.readable.copyWith(
                color: isSelected ? AppColors.primary : AppColors.ink,
              ),
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
class _MultiSelectSheet extends StatefulWidget {
  const _MultiSelectSheet({
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
      child: _MultiSelectSheet(
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
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
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
        return const _Note(InboxFilterController.conditionsNeedOneFormText);
      }
      if (!panel.hasOneForm(block)) {
        return const _Note(InboxFilterController.conditionsManyFormsText);
      }
      if (state == InboxKindsState.failed) {
        return const _Note(InboxFilterController.conditionsUnavailableText);
      }
      if (state != InboxKindsState.ready) {
        return const _Note(InboxFilterController.conditionsLoadingText);
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

class _Note extends StatelessWidget {
  const _Note(this.text);

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
                                _Chip(
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
            _SelectLine(
              label: 'Field',
              summary: field?.label ?? 'Choose a field',
              hasValue: field != null,
              onTap: () => _SingleSelectSheet.show(
                context,
                title: 'Field',
                choices: () => panel.fieldChoices(block),
                selected: () => _now().field,
                onPicked: (id) => panel.setConditionField(block.id, c.id, id),
              ),
            ),
            if (c.field.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _SelectLine(
                label: 'Operator',
                summary: op?.label ?? 'Choose',
                hasValue: op != null,
                onTap: () => _SingleSelectSheet.show(
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
          return _DateLine(
            label: label,
            value: text,
            first: DateTime(1900),
            last: DateTime(2100),
            onPicked: set,
            emptyText: 'Choose a day',
          );
        });
      }
      return _ValueField(
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
class _ValueField extends StatefulWidget {
  const _ValueField({
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
  State<_ValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<_ValueField> {
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
class _SingleSelectSheet extends StatefulWidget {
  const _SingleSelectSheet({
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
      child: _SingleSelectSheet(
        title: title,
        choices: choices,
        selected: selected,
        onPicked: onPicked,
        isSearchable: isSearchable,
      ),
    );
  }

  @override
  State<_SingleSelectSheet> createState() => _SingleSelectSheetState();
}

class _SingleSelectSheetState extends State<_SingleSelectSheet> {
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
