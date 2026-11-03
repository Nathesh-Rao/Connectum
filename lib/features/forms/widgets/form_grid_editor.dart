import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../form_controller.dart';
import '../models/field_input.dart';
import 'form_field_row.dart';

/// A grid section: one card per row with the section's fields as its columns,
/// remove on each row, and Add row under them.
class FormGridEditor extends StatelessWidget {
  const FormGridEditor({
    super.key,
    required this.controller,
    required this.grid,
  });

  final FormController controller;
  final GridInput grid;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      key: grid.key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final rows = grid.rows.toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++)
                _RowCard(
                  key: ValueKey(rows[i].id),
                  controller: c,
                  grid: grid,
                  row: rows[i],
                  index: i,
                ),
            ],
          );
        }),
        Obx(() {
          final error = grid.error.value;
          return error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(error, style: AppText.error),
                );
        }),
        Obx(
          () => AppButton.secondary(
            label: 'Add row',
            icon: Icons.add,
            onPressed: grid.rows.length >= FormController.maxRows
                ? null
                : () => c.addRow(grid),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    super.key,
    required this.controller,
    required this.grid,
    required this.row,
    required this.index,
  });

  final FormController controller;
  final GridInput grid;
  final RowInput row;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Row ${index + 1}', style: AppText.label)),
              AppButton.icon(
                icon: Icons.delete_outline,
                semanticLabel: 'Remove row ${index + 1}',
                onPressed: () => controller.removeRow(grid, row),
              ),
            ],
          ),
          for (final column in grid.columns)
            FormFieldRow(
              controller: controller,
              input: row.fields[column.name]!,
              row: row,
            ),
        ],
      ),
    );
  }
}
