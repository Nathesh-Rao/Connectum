import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import '../../data/form_logic/sample_forms.dart';
import '../../data/models/ids.dart';
import 'condition_vectors.dart';
import 'input_vectors.dart';
import 'debug_forms_controller.dart';

class DebugFormsView extends GetView<DebugFormsController> {
  const DebugFormsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Obx(() {
        final s = c.shape.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            const Text('Sample forms (read only)', style: AppText.title),
            Text(
              'org ${c.session.orgId ?? '-'} · nothing is saved or submitted',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!c.isReady)
              const _Line(
                'Sign in to an organisation and connect first.',
                isOk: false,
              )
            else if (s == null)
              ..._list(c)
            else
              ..._form(c, s),
            if (c.error.value != null) _Line(c.error.value!, isOk: false),
            if (s == null) ..._cache(c),
            if (s == null) ..._inputs(),
            if (s == null) ..._conditions(),
            const SizedBox(height: AppSpacing.xl),
          ],
        );
      }),
    );
  }

  /// The kept lists of `form.options`: key, expiry, the two-day limit and
  /// each drop rule.
  List<Widget> _cache(DebugFormsController c) {
    final results = c.cacheResults.toList();
    final failed = results.where((r) => !r.isOk).length;
    return [
      const SizedBox(height: AppSpacing.md),
      _Head(
        results.isEmpty
            ? 'Kept lists (form.options)'
            : 'Kept lists (form.options)  '
                  '(${results.length - failed} pass, $failed fail)',
      ),
      AppButton.secondary(
        label: 'Run kept-lists checks',
        onPressed: c.runCacheVectors,
      ),
      for (final r in results) _Line(r.line, isOk: r.isOk),
    ];
  }

  /// What each field type keeps while typing, what the local check says and
  /// what is sent, on the `sample_types` fields. No server is needed.
  List<Widget> _inputs() {
    final results = InputVectors.run();
    final failed = results.where((r) => !r.isOk).length;
    return [
      const SizedBox(height: AppSpacing.md),
      _Head(
        'Input behaviour on sample_types  '
        '(${results.length - failed} pass, $failed fail)',
      ),
      for (final r in results) _Line(r.line, isOk: r.isOk),
    ];
  }

  /// The temporary condition evaluator against the web's `evalCondition`.
  /// A DIFF is a known difference, not a failure to fix in Dart.
  List<Widget> _conditions() {
    final differ = conditionVectors.where((v) => !v.isSame).toList();
    return [
      const SizedBox(height: AppSpacing.md),
      _Head(
        'Conditions: temporary evaluator vs web evalCondition  '
        '(${conditionVectors.length - differ.length} same, ${differ.length} differ)',
      ),
      for (final v in conditionVectors)
        _Line(
          '${v.isSame ? 'SAME' : 'DIFF'}  ${v.name}\n'
          '  web ${v.web}${v.isDocumented ? ' (per doc)' : ''}, temporary ${v.temporary}',
          isOk: v.isSame,
        ),
    ];
  }

  List<Widget> _list(DebugFormsController c) => [
    if (c.isLoading.value) const _Line('loading…'),
    for (final o in c.forms)
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: AppButton.secondary(
          label:
              '${o.target}  (${o.targetScope.isEmpty ? 'admin' : o.targetScope})',
          onPressed: () => c.open(o),
        ),
      ),
    if (!c.isLoading.value && c.forms.isEmpty)
      const _Line('No sample_* forms are offered to this person.'),
    const SizedBox(height: AppSpacing.sm),
    AppButton.secondary(label: 'Reload list', onPressed: c.load),
    const SizedBox(height: AppSpacing.sm),
    AppButton.primary(
      label: 'Check all against cases.json',
      isLoading: c.isChecking.value,
      onPressed: c.checkAll,
    ),
    ..._results(c.results),
  ];

  List<Widget> _results(List<SampleFormResult> results) => [
    for (final r in results) ...[
      _Line(r.line, isOk: r.isOk),
      for (final f in r.failures) _Line(f, isOk: false),
    ],
    if (results.isNotEmpty)
      _Head(
        'cases passing: ${results.fold<int>(0, (a, r) => a + r.passed)}'
        ' / ${results.fold<int>(0, (a, r) => a + r.total)}',
      ),
  ];

  List<Widget> _form(DebugFormsController c, FormShape s) {
    final calc = c.calculated;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '${c.openName.value}  ${idText(s.tstruct['caption'])}',
              style: AppText.bodyStrong,
            ),
          ),
          AppButton.text(label: 'Back', onPressed: c.close),
        ],
      ),
      if (c.logicError.value != null)
        _Line('logic: ${c.logicError.value}', isOk: false),
      for (final f in s.fields) _field(c, f, calc[idText(f['name'])]),
      for (final g in s.gridNames) ...[
        _Head('Grid $g  (${c.rowCounts[g] ?? 0} rows)'),
        for (var i = 0; i < (c.rowCounts[g] ?? 0); i++) ...[
          _Line('row ${i + 1}'),
          for (final f in s.grids[g] ?? const <Map<String, dynamic>>[])
            _cell(c, g, i, f, calc),
        ],
        Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                label: 'Add row',
                onPressed: () => c.addRow(g),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: AppButton.secondary(
                label: 'Remove row',
                onPressed: () => c.removeRow(g),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _field(DebugFormsController c, Map<String, dynamic> f, Object? value) {
    final name = idText(f['name']);
    final isCalc = f['calc'] is Map;
    final isShown = c.visible[name] ?? true;
    final message = c.ruleMessages[name];
    return _Box(
      isDim: !isShown,
      children: [
        Text(
          '$name · ${idText(f['caption'])}  ${isShown ? '[visible]' : '[hidden by condition]'}',
          style: AppText.bodyStrong,
        ),
        _Line(c.describe(f)),
        if (isCalc)
          _Line(
            'calculated: ${idText(value).isEmpty ? '(empty)' : idText(value)}',
            isOk: true,
          )
        else
          AppTextField(
            controller: c.inputFor(name),
            hint: 'type a value',
            onChanged: (t) => c.setValue(name, t),
          ),
        if (message != null) _Line('rule: $message', isOk: false),
      ],
    );
  }

  Widget _cell(
    DebugFormsController c,
    String section,
    int row,
    Map<String, dynamic> f,
    Map<String, dynamic> calc,
  ) {
    final name = idText(f['name']);
    final key = '$section.$row.$name';
    final rows = calc[section] as List? ?? const [];
    final cells = row < rows.length && rows[row] is Map
        ? rows[row] as Map
        : const {};
    final message = c.ruleMessages[key];
    return _Box(
      children: [
        Text('$name · ${idText(f['caption'])}', style: AppText.bodyStrong),
        _Line(c.describe(f)),
        if (f['calc'] is Map)
          _Line(
            'calculated: ${idText(cells[name]).isEmpty ? '(empty)' : idText(cells[name])}',
            isOk: true,
          )
        else
          AppTextField(
            controller: c.inputFor(key),
            hint: 'type a value',
            onChanged: (t) => c.setValue(key, t),
          ),
        if (message != null) _Line('rule: $message', isOk: false),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.children, this.isDim = false});

  final List<Widget> children;
  final bool isDim;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: isDim ? 0.45 : 1,
    child: Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _Head extends StatelessWidget {
  const _Head(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxs),
    child: Text(text, style: AppText.bodyStrong),
  );
}

class _Line extends StatelessWidget {
  const _Line(this.text, {this.isOk});

  final String text;
  final bool? isOk;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: SelectableText(
      text,
      style: AppText.caption.copyWith(
        fontFamily: 'monospace',
        color: switch (isOk) {
          true => AppColors.yesText,
          false => AppColors.error,
          null => null,
        },
      ),
    ),
  );
}
