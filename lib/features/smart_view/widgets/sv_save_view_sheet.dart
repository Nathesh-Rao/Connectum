import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/smart_view/sv_saved_view.dart';
import '../smart_view_controller.dart';

/// "Save view": a name and a summary of what the view will hold (the
/// current filters, sort, grouping and columns). With [renameId] it only
/// asks for a new name.
class SvSaveViewSheet {
  SvSaveViewSheet._();

  static Future<void> show(
    BuildContext context,
    SmartViewController c, {
    String? renameId,
    String initial = '',
  }) {
    return AppBottomSheet.show<void>(
      context,
      title: renameId == null ? 'Save view' : 'Rename view',
      child: SvSaveViewBody(
        controller: c,
        renameId: renameId,
        initial: initial,
        onDone: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  /// The lines under the name: what Save will keep.
  static List<String> summary(SmartViewController c) {
    final w = c.working;
    final cols = c.columns?.columns ?? const [];
    String label(String key) =>
        cols.where((x) => x.key == key).firstOrNull?.label ?? key;
    final shown = c.shownColumns?.listable.length ?? 0;
    final n = w.filterCount;
    return [
      n == 0 ? 'No filters' : '$n ${n == 1 ? 'filter' : 'filters'}',
      w.query.sortKey == null
          ? 'No sort'
          : 'Sort: ${label(w.query.sortKey!)}'
                ' (${w.query.isAscending ? 'ascending' : 'descending'})',
      w.groupBy.isEmpty
          ? 'No grouping'
          : 'Group by: ${w.groupBy.map((g) => label(SvKeys.mobile(g))).join(' › ')}',
      '$shown ${shown == 1 ? 'column' : 'columns'}',
    ];
  }
}

class SvSaveViewBody extends StatefulWidget {
  const SvSaveViewBody({
    super.key,
    required this.controller,
    required this.onDone,
    this.renameId,
    this.initial = '',
  });

  final SmartViewController controller;
  final VoidCallback onDone;
  final String? renameId;
  final String initial;

  @override
  State<SvSaveViewBody> createState() => _SvSaveViewBodyState();
}

class _SvSaveViewBodyState extends State<SvSaveViewBody> {
  late final _field = TextEditingController(text: widget.initial);
  final _error = ''.obs;
  final _isBusy = false.obs;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = SvSavedView.cleanName(_field.text);
    if (name.isEmpty) {
      _error.value = 'Give the view a name.';
      return;
    }
    if (name.toLowerCase() == SvViewLimits.defaultName.toLowerCase()) {
      _error.value = 'That name is taken by the Default View.';
      return;
    }
    _error.value = '';
    _isBusy.value = true;
    final c = widget.controller;
    final ok = widget.renameId == null
        ? await c.saveAsNew(name)
        : await c.renameView(widget.renameId!, name);
    _isBusy.value = false;
    if (ok) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.renameId == null
        ? SvSaveViewSheet.summary(widget.controller)
        : const <String>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => AppTextField(
            controller: _field,
            hint: 'View name',
            autofocus: true,
            maxLength: SvViewLimits.maxName,
            errorText: _error.value.isEmpty ? null : _error.value,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => _error.value = '',
          ),
        ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                l,
                style: AppText.readable.copyWith(color: AppColors.muted),
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppButton.primary(
            label: widget.renameId == null ? 'Save' : 'Rename',
            isLoading: _isBusy.value,
            onPressed: _isBusy.value ? null : _save,
          ),
        ),
      ],
    );
  }
}
