import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/form_option.dart';

/// Picks one or several of a list's choices. A long list gets a search field.
class ChoiceSheet extends StatefulWidget {
  const ChoiceSheet({
    super.key,
    required this.choices,
    required this.selected,
    required this.isMulti,
    required this.onDone,
  });

  static const searchFrom = 8;

  final List<FormChoice> choices;
  final List<String> selected;
  final bool isMulti;
  final ValueChanged<List<String>> onDone;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<FormChoice> choices,
    required List<String> selected,
    required bool isMulti,
    required ValueChanged<List<String>> onDone,
  }) => AppBottomSheet.show<void>(
    context,
    title: title,
    child: ChoiceSheet(
      choices: choices,
      selected: selected,
      isMulti: isMulti,
      onDone: onDone,
    ),
  );

  @override
  State<ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<ChoiceSheet> {
  final _search = TextEditingController();
  late final _picked = <String>{...widget.selected}.obs;
  final _query = ''.obs;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _tap(FormChoice c) {
    if (widget.isMulti) {
      _picked.contains(c.value)
          ? _picked.remove(c.value)
          : _picked.add(c.value);
      return;
    }
    widget.onDone([c.value]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasSearch = widget.choices.length > ChoiceSheet.searchFrom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasSearch) ...[
          AppTextField(
            controller: _search,
            hint: 'Search',
            minHeight: AppSpacing.searchHeight,
            fillColor: AppColors.surface,
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
            leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
            onChanged: (v) => _query.value = v.trim().toLowerCase(),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Obx(() {
          final q = _query.value;
          final shown = [
            for (final c in widget.choices)
              if (q.isEmpty || c.label.toLowerCase().contains(q)) c,
          ];
          if (shown.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('Nothing matches.', style: AppText.readable),
            );
          }
          return Column(
            children: [
              for (final c in shown)
                AppListRow(
                  title: c.label,
                  minHeight: AppSpacing.settingRowHeight,
                  trailing: _picked.contains(c.value)
                      ? const Icon(
                          Icons.check,
                          size: 20,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () => _tap(c),
                ),
            ],
          );
        }),
        if (widget.isMulti) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton.primary(
            label: 'Done',
            isCentered: true,
            onPressed: () {
              widget.onDone([
                for (final c in widget.choices)
                  if (_picked.contains(c.value)) c.value,
              ]);
              Navigator.of(context).pop();
            },
          ),
        ],
      ],
    );
  }
}
