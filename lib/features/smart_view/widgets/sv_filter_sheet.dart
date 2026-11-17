import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_popup_menu.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/smart_view/engine/sv_engine.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../smart_view_controller.dart';
import 'sv_col_icon.dart';
import 'sv_filter_draft.dart';
import 'sv_pill.dart';

/// The filter sheet: one line per condition (field, operator, value), a live
/// "N of M records" and Apply. Edits live in a draft; closing without Apply
/// drops them.
class SvFilterSheet {
  SvFilterSheet._();

  static Future<void> show(BuildContext context, SmartViewController c) {
    final input = c.engineInput;
    if (input == null) return Future.value();
    final draft = SvFilterDraft(input, c.query.value);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.sheetBackdrop,
      elevation: 0,
      sheetAnimationStyle: AnimationStyle(
        duration: AppDurations.slow,
        reverseDuration: AppDurations.base,
        curve: AppCurves.sheet,
        reverseCurve: AppCurves.out,
      ),
      builder: (sheet) => Stack(
        children: [
          // The sheet fills the route, so the area above it would swallow
          // the tap that should dismiss it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(sheet).pop(),
            ),
          ),
          Positioned.fill(
            child: SvFilterSheetBody(
              draft: draft,
              onApply: () {
                c.setConditions(draft.conditions);
                Navigator.of(sheet).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SvFilterSheetBody extends StatelessWidget {
  const SvFilterSheetBody({
    super.key,
    required this.draft,
    required this.onApply,
  });

  final SvFilterDraft draft;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      snap: true,
      builder: (context, scroll) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.sheetTop,
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  controller: scroll,
                  slivers: [
                    SliverToBoxAdapter(child: _Header(draft: draft)),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sheetPaddingX,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Obx(
                          () => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (draft.rows.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                  ),
                                  child: Text(
                                    'No filters yet. Add one to narrow the list.',
                                    style: AppText.supporting,
                                  ),
                                ),
                              for (final r in draft.rows)
                                _FadeSlideIn(
                                  key: ValueKey('sv-draft-${r.id}'),
                                  child: _FilterRow(draft: draft, row: r),
                                ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AppButton.text(
                                  label: 'Add filter',
                                  leadingIcon: Icons.add,
                                  tone: AppTextButtonTone.accent,
                                  onPressed: draft.add,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _Bar(draft: draft, onApply: onApply),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.draft});

  final SvFilterDraft draft;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sheetPaddingX,
        AppSpacing.sheetPaddingTop,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              width: AppSpacing.handleWidth,
              height: AppSpacing.handleHeight,
              decoration: const BoxDecoration(
                color: AppColors.sheetHandle,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Expanded(child: Text('Filters', style: AppText.subtitle)),
              Obx(
                () => AppButton.text(
                  label: 'Clear all',
                  onPressed: draft.rows.isEmpty ? null : draft.clear,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.draft, required this.onApply});

  final SvFilterDraft draft;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.sheetPaddingX,
          AppSpacing.sm,
          AppSpacing.sheetPaddingX,
          AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
        ),
        child: Row(
          children: [
            Expanded(
              child: Obx(
                () => Text(
                  '${draft.count} of ${draft.total} records',
                  style: AppText.bodyStrong,
                ),
              ),
            ),
            SizedBox(
              width: 132,
              child: AppButton.primary(
                label: 'Apply',
                isCompact: true,
                isCentered: true,
                onPressed: onApply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A gentle fade and short slide when a line appears.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.smartChip,
      curve: AppCurves.out,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * AppDistances.tab),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.draft, required this.row});

  final SvFilterDraft draft;
  final SvDraftRow row;

  @override
  Widget build(BuildContext context) {
    final col = draft.colOf(row.col);
    if (col == null) return const SizedBox.shrink();
    final kind = draft.kindOf(col, row.op);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceSubtle,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xxs,
            AppSpacing.xxs,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Builder(
                            builder: (anchor) => SvPill(
                              label: col.label,
                              maxWidth: 170,
                              onTap: () => _pickField(anchor),
                            ),
                          ),
                        ),
                        if (kind != SvValueKind.tristate) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Builder(
                              builder: (anchor) => SvPill(
                                label: SvEngine.opLabel(row.op),
                                maxWidth: 140,
                                onTap: () => _pickOp(anchor, col),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove filter',
                    constraints: const BoxConstraints.tightFor(
                      width: AppSpacing.badgedIconHit,
                      height: AppSpacing.badgedIconHit,
                    ),
                    icon: const Icon(
                      Icons.close,
                      size: AppSpacing.popupMenuIcon,
                      color: AppColors.muted,
                    ),
                    onPressed: () => draft.remove(row.id),
                  ),
                ],
              ),
              if (kind != SvValueKind.none)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: _ValueEditor(
                    key: ValueKey('${row.id}-${kind.name}'),
                    draft: draft,
                    row: row,
                    column: col,
                    kind: kind,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickField(BuildContext anchor) {
    AppPopupMenuCard.show(anchor, [
      for (final f in draft.fields)
        AppMenuItem(
          icon: f.key == row.col ? Icons.check : SvColIcon.of(f.type),
          label: f.label,
          onTap: () => draft.setCol(row.id, f),
        ),
    ]);
  }

  void _pickOp(BuildContext anchor, SvColumn col) {
    AppPopupMenuCard.show(anchor, [
      for (final op in draft.opsOf(col))
        AppMenuItem(
          icon: op == row.op ? Icons.check : Icons.chevron_right,
          label: SvEngine.opLabel(op),
          onTap: () => draft.setOp(row.id, op),
        ),
    ]);
  }
}

class _ValueEditor extends StatelessWidget {
  const _ValueEditor({
    super.key,
    required this.draft,
    required this.row,
    required this.column,
    required this.kind,
  });

  final SvFilterDraft draft;
  final SvDraftRow row;
  final SvColumn column;
  final SvValueKind kind;

  Map<String, Object?> get _range {
    final v = row.value;
    return v is Map ? v.cast<String, Object?>() : const {};
  }

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case SvValueKind.text:
        return _TextValue(
          initial: '${row.value ?? ''}',
          hint: 'Value',
          onChanged: (v) => draft.setValue(row.id, v),
        );
      case SvValueKind.number:
        return _TextValue(
          initial: '${row.value ?? ''}',
          hint: 'Number',
          isNumber: true,
          onChanged: (v) => draft.setValue(row.id, v),
        );
      case SvValueKind.numberRange:
        return Row(
          children: [
            Expanded(
              child: _TextValue(
                initial: '${_range['from'] ?? ''}',
                hint: 'From',
                isNumber: true,
                onChanged: (v) =>
                    draft.setValue(row.id, {..._range, 'from': v}),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _TextValue(
                initial: '${_range['to'] ?? ''}',
                hint: 'To',
                isNumber: true,
                onChanged: (v) => draft.setValue(row.id, {..._range, 'to': v}),
              ),
            ),
          ],
        );
      case SvValueKind.date:
        return _DateValue(
          hint: 'Pick a date',
          value: row.value as String?,
          onPicked: (v) => draft.setValue(row.id, v),
        );
      case SvValueKind.dateRange:
        return Row(
          children: [
            Expanded(
              child: _DateValue(
                hint: 'From',
                value: _range['from'] as String?,
                onPicked: (v) => draft.setValue(row.id, {..._range, 'from': v}),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _DateValue(
                hint: 'To',
                value: _range['to'] as String?,
                onPicked: (v) => draft.setValue(row.id, {..._range, 'to': v}),
              ),
            ),
          ],
        );
      case SvValueKind.choice:
        final chosen = {for (final v in (row.value as List? ?? const [])) '$v'};
        void toggle(String v) {
          final next = chosen.contains(v)
              ? (chosen.toList()..remove(v))
              : [...chosen, v];
          draft.setValue(row.id, next);
        }

        final values = draft.input.distinct(
          column.key,
          limit: SvFilterDraft.maxChoices,
        );
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final v in values)
                SvChoiceChip(
                  label: v,
                  isOn: chosen.contains(v),
                  onTap: () => toggle(v),
                ),
            ],
          ),
        );
      case SvValueKind.tristate:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final o in const [
                ('', 'Any'),
                ('true', 'Yes'),
                ('false', 'No'),
              ])
                SvChoiceChip(
                  label: o.$2,
                  isOn: row.op == o.$1,
                  onTap: () => draft.setOp(row.id, o.$1),
                ),
            ],
          ),
        );
      case SvValueKind.none:
        return const SizedBox.shrink();
    }
  }
}

/// A selectable chip: filled violet when on.
class SvChoiceChip extends StatelessWidget {
  const SvChoiceChip({
    super.key,
    required this.label,
    required this.isOn,
    required this.onTap,
  });

  final String label;
  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isOn,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: AnimatedContainer(
              duration: AppDurations.smartChip,
              curve: AppCurves.out,
              height: AppSpacing.pillTall,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: isOn ? AppColors.violet : AppColors.white,
                borderRadius: AppRadius.pillAll,
                border: Border.all(
                  color: isOn ? AppColors.violet : AppColors.inputBorder,
                ),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: AppText.readableStrong.copyWith(
                    color: isOn ? AppColors.white : AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextValue extends StatefulWidget {
  const _TextValue({
    required this.initial,
    required this.hint,
    required this.onChanged,
    this.isNumber = false,
  });

  final String initial;
  final String hint;
  final bool isNumber;
  final ValueChanged<String> onChanged;

  @override
  State<_TextValue> createState() => _TextValueState();
}

class _TextValueState extends State<_TextValue> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      hint: widget.hint,
      minHeight: AppSpacing.minTapTarget,
      maxLength: 200,
      keyboardType: widget.isNumber
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      inputFormatters: widget.isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-+$%]'))]
          : null,
      textStyle: AppText.body,
      onChanged: widget.onChanged,
    );
  }
}

class _DateValue extends StatelessWidget {
  const _DateValue({
    required this.hint,
    required this.value,
    required this.onPicked,
  });

  final String hint;
  final String? value;
  final ValueChanged<String> onPicked;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return Semantics(
      button: true,
      label: has ? '$hint, $value' : hint,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final start = has ? DateTime.tryParse(value!) : null;
          final picked = await showDatePicker(
            context: context,
            initialDate: start ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2100),
          );
          if (picked != null) onPicked(_iso(picked));
        },
        child: Container(
          height: AppSpacing.minTapTarget,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: AppRadius.controlAll,
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: AppSpacing.navIcon - 4,
                color: AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  has ? value! : hint,
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
    );
  }
}
