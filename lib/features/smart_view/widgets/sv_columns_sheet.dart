import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../../../data/smart_view/sv_saved_view.dart';
import '../smart_view_controller.dart';
import 'sv_field_row.dart';

/// "Select fields": search, Select all, a checklist (caption and muted key;
/// the By, Submitted and Status columns are in it) you can reorder by
/// dragging while the search is empty, Reset and Apply. It edits the working
/// view only. Hidden form fields are not offered: they are not in the
/// source list (see the BE questions).
class SvColumnsSheet {
  SvColumnsSheet._();

  static Future<void> show(BuildContext context, SmartViewController c) {
    return AppBottomSheet.show<void>(
      context,
      title: 'Select fields',
      child: SvColumnsBody(
        controller: c,
        onDone: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class SvColumnsBody extends StatefulWidget {
  const SvColumnsBody({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final SmartViewController controller;
  final VoidCallback onDone;

  @override
  State<SvColumnsBody> createState() => _SvColumnsBodyState();
}

class _SvColumnsBodyState extends State<SvColumnsBody> {
  final _search = TextEditingController();
  final _text = ''.obs;
  late final List<SvColumn> _natural = [
    ...widget.controller.columns?.listable ?? const <SvColumn>[],
  ];

  /// Every column in the draft's order: the shown ones first (as the view
  /// lays them out), then the ones turned off.
  late final _ordered = _initialOrder().obs;
  late final _ticked = {
    for (final c in widget.controller.shownColumns?.listable ?? const []) c.key,
  }.obs;

  List<SvColumn> _initialOrder() {
    final shown = widget.controller.shownColumns?.listable ?? const [];
    return [
      ...shown,
      for (final c in _natural)
        if (!shown.any((s) => s.key == c.key)) c,
    ];
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    if (!_ticked.remove(key)) _ticked.add(key);
  }

  void _selectAll(List<SvColumn> visible) {
    final all = visible.every((c) => _ticked.contains(c.key));
    for (final c in visible) {
      if (all) {
        _ticked.remove(c.key);
      } else {
        _ticked.add(c.key);
      }
    }
  }

  void _reset() {
    _ordered.assignAll(_natural);
    _ticked
      ..clear()
      ..addAll(_natural.map((c) => c.key));
  }

  void _apply() {
    final c = widget.controller;
    final known = {for (final x in _natural) SvKeys.web(x.key)};
    bool foreign(String e) =>
        !known.contains(e.startsWith('+') ? e.substring(1) : e);
    final hidden = [
      ...c.hidden.where(foreign),
      for (final x in _natural)
        if (!_ticked.contains(x.key)) SvKeys.web(x.key),
    ];
    final onKeys = [
      for (final x in _ordered)
        if (_ticked.contains(x.key)) SvKeys.web(x.key),
    ];
    final naturalOn = [
      for (final x in _natural)
        if (_ticked.contains(x.key)) SvKeys.web(x.key),
    ];
    final same =
        onKeys.length == naturalOn.length &&
        [
          for (var i = 0; i < onKeys.length; i++) onKeys[i] == naturalOn[i],
        ].every((b) => b);
    c.setColumns(hidden, same ? const [] : onKeys);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
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
        Obx(() {
          final q = _text.value;
          final visible = [
            for (final c in _ordered)
              if (q.isEmpty ||
                  c.label.toLowerCase().contains(q) ||
                  c.key.toLowerCase().contains(q))
                c,
          ];
          final all =
              visible.isNotEmpty &&
              visible.every((c) => _ticked.contains(c.key));
          return Align(
            alignment: Alignment.centerLeft,
            child: AppButton.text(
              label: all ? 'Clear all' : 'Select all',
              onPressed: () => _selectAll(visible),
            ),
          );
        }),
        Flexible(
          child: Obx(() {
            final q = _text.value;
            final ticked = _ticked.toSet();
            if (q.isEmpty) {
              return ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                onReorder: (from, to) {
                  final list = _ordered.toList();
                  if (to > from) to--;
                  list.insert(to, list.removeAt(from));
                  _ordered.assignAll(list);
                },
                children: [
                  for (var i = 0; i < _ordered.length; i++)
                    SvFieldRow(
                      key: ValueKey('col-${_ordered[i].key}'),
                      label: _ordered[i].label,
                      name: SvKeys.web(_ordered[i].key),
                      isTicked: ticked.contains(_ordered[i].key),
                      dragIndex: i,
                      onTap: () => _toggle(_ordered[i].key),
                    ),
                ],
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                for (final c in _ordered)
                  if (c.label.toLowerCase().contains(q) ||
                      c.key.toLowerCase().contains(q))
                    SvFieldRow(
                      label: c.label,
                      name: SvKeys.web(c.key),
                      isTicked: ticked.contains(c.key),
                      onTap: () => _toggle(c.key),
                    ),
              ],
            );
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            AppButton.text(label: 'Reset', onPressed: _reset),
            const Spacer(),
            SizedBox(
              width: 140,
              child: Obx(
                () => AppButton.primary(
                  label: 'Apply',
                  onPressed: _ticked.isEmpty ? null : _apply,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
