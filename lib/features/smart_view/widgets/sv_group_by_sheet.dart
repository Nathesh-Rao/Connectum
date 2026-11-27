import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../../../data/smart_view/sv_saved_view.dart';
import '../smart_view_controller.dart';
import 'sv_field_row.dart';

/// "Group by": search, a checklist of fields; the order they are ticked in
/// is the group order (numbered badges). Clear removes the grouping, Apply
/// sets it; closing the sheet cancels. Edits the working state only.
class SvGroupBySheet {
  SvGroupBySheet._();

  static Future<void> show(BuildContext context, SmartViewController c) {
    return AppBottomSheet.show<void>(
      context,
      title: 'Group by',
      child: SvGroupByBody(
        controller: c,
        onDone: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class SvGroupByBody extends StatefulWidget {
  const SvGroupByBody({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final SmartViewController controller;
  final VoidCallback onDone;

  @override
  State<SvGroupByBody> createState() => _SvGroupByBodyState();
}

class _SvGroupByBodyState extends State<SvGroupByBody> {
  final _search = TextEditingController();
  final _text = ''.obs;
  late final _ticked = widget.controller.groupBy.toList().obs;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String webKey) {
    if (!_ticked.remove(webKey)) {
      if (_ticked.length >= SvViewLimits.maxGroups) {
        AppNotices.warning('Group by at most 5 fields.');
        return;
      }
      _ticked.add(webKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cols = [
      for (final col in c.columns?.listable ?? const <SvColumn>[])
        if (col.type != SvColType.file) col,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _search,
          hint: 'Search fields',
          onChanged: (v) => _text.value = v.trim().toLowerCase(),
        ),
        const SizedBox(height: AppSpacing.xs),
        Flexible(
          child: Obx(() {
            final q = _text.value;
            final ticked = _ticked.toList();
            return ListView(
              shrinkWrap: true,
              children: [
                for (final col in cols)
                  if (q.isEmpty ||
                      col.label.toLowerCase().contains(q) ||
                      col.key.toLowerCase().contains(q))
                    SvFieldRow(
                      label: col.label,
                      name: SvKeys.web(col.key),
                      isTicked: ticked.contains(SvKeys.web(col.key)),
                      level: ticked.contains(SvKeys.web(col.key))
                          ? ticked.indexOf(SvKeys.web(col.key)) + 1
                          : null,
                      onTap: () => _toggle(SvKeys.web(col.key)),
                    ),
              ],
            );
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            AppButton.text(
              label: 'Clear',
              onPressed: () {
                c.setGroupBy(const []);
                widget.onDone();
              },
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              child: AppButton.primary(
                label: 'Apply',
                onPressed: () {
                  c.setGroupBy(_ticked.toList());
                  widget.onDone();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
