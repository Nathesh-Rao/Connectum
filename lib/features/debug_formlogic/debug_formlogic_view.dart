import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../data/form_logic/form_logic_runner.dart';
import 'debug_formlogic_controller.dart';

class DebugFormLogicView extends GetView<DebugFormLogicController> {
  const DebugFormLogicView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Obx(() {
        final r = c.report.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            const Text('Form logic engine', style: AppText.title),
            Text(
              'manifest ${c.version.value ?? '-'}; QuickJS-NG in a background isolate',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final line in c.checks) _Line(line, isOk: true),
            if (c.isRunning.value) const _Line('running…'),
            if (c.error.value != null) _Line(c.error.value!, isOk: false),
            if (r != null) ..._report(r),
            const SizedBox(height: AppSpacing.md),
            AppButton.primary(label: 'Run again', onPressed: c.run),
            const _Head('Sample forms (read only, needs sign-in)'),
            if (!c.canCheckSamples)
              const _Line(
                'Sign in to an organisation and connect to run these.',
              )
            else
              AppButton.secondary(
                label: 'Check sample_* forms',
                isLoading: c.isCheckingSamples.value,
                onPressed: c.checkSamples,
              ),
            if (c.sampleError.value != null)
              _Line(c.sampleError.value!, isOk: false),
            for (final x in c.sampleResults) ...[
              _Line(x.line, isOk: x.isOk),
              for (final f in x.failures) _Line(f, isOk: false),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        );
      }),
    );
  }

  List<Widget> _report(FormLogicReport r) {
    final conf = r.conformance;
    final failures = (conf['failures'] as List).cast<Map<String, dynamic>>();
    final exprFailures = [
      for (final f in failures)
        if (!f.containsKey('condition')) f,
    ];
    final condFailures = [
      for (final f in failures)
        if (f.containsKey('condition')) f,
    ];
    final p = r.probe;
    final now = DateTime.parse(r.dartNow);
    String two(int n) => n.toString().padLeft(2, '0');
    final dartDate = '${two(now.day)}/${two(now.month)}/${now.year}';
    final dartTime = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final jsDate = p['jsDate'] as String;
    final jsTime = p['jsTime'] as String;
    final timeClose = _secondsApart(dartTime, jsTime) <= 5;
    final parityFailed = r.parity.where((x) => (x['diffs'] as List).isNotEmpty);

    return [
      _Head(
        'Conformance (runConformance): total ${conf['total']}, '
        'passed ${conf['passed']}, failures ${failures.length}',
      ),
      _Line(
        'expressions  total ${r.expressionTotal}, passed ${r.expressionTotal - exprFailures.length}, failures ${exprFailures.length}',
        isOk: exprFailures.isEmpty,
      ),
      _Line(
        'conditions   total ${r.conditionTotal}, passed ${r.conditionTotal - condFailures.length}, failures ${condFailures.length}',
        isOk: condFailures.isEmpty,
      ),
      for (final f in exprFailures)
        _Line(
          '${f['expr']}\n  expected ${f['expected']}\n  got ${f['got']}',
          isOk: false,
        ),
      for (final f in condFailures)
        _Line(
          '${jsonEncode(f['condition'])} with ${jsonEncode(f['values'])}\n'
          '  expected ${f['expected']}\n  got ${f['got']}',
          isOk: false,
        ),
      const _Head('Date() / Time() in this time zone'),
      _Line(
        'Dart now   $dartDate $dartTime  (UTC${_offset(r.dartOffsetMinutes)})',
      ),
      _Line(
        'JS Date()   $jsDate   ${jsDate == dartDate ? 'match' : 'MISMATCH'}',
        isOk: jsDate == dartDate,
      ),
      _Line(
        'JS Time()   $jsTime   ${timeClose ? 'match (±5 s)' : 'MISMATCH'}',
        isOk: timeClose,
      ),
      _Line(
        'JS offset   UTC${_offset(p['jsOffsetMinutes'] as int)}   '
        '${p['jsOffsetMinutes'] == r.dartOffsetMinutes ? 'match' : 'MISMATCH'}',
        isOk: p['jsOffsetMinutes'] == r.dartOffsetMinutes,
      ),
      _Head(
        'Local date and time of fixed instants (engine vs Dart; '
        'this phone is UTC${_offset(r.dartOffsetMinutes)})',
      ),
      for (final z in r.zone)
        _Line(
          '${z['iso']}\n  JS ${z['js']}   Dart ${z['dart']}   '
          '${z['js'] == z['dart'] ? 'match' : 'MISMATCH'}'
          '${r.dartOffsetMinutes == 330 ? '   India expects ${z['inIndia']}  '
                    '${z['js'] == z['inIndia'] ? 'ok' : 'WRONG'}' : ''}',
          isOk:
              z['js'] == z['dart'] &&
              (r.dartOffsetMinutes != 330 || z['js'] == z['inIndia']),
        ),
      const _Head('SetDateFormat on LastDayOfMonth("03/04/2026")'),
      _Line('dd/mm/yyyy   Date() ${p['dmyDate']}   last day ${p['dmyLast']}'),
      _Line('mm/dd/yyyy   Date() ${p['mdyDate']}   last day ${p['mdyLast']}'),
      const _Head('Timings (background isolate)'),
      _Line('engine load (shim + bundle)  ${_ms(r.loadMicros)}'),
      _Line('one Evaluate, median of 200  ${_ms(r.evalMedianMicros)}'),
      _Head(
        'Parity vectors: ${r.parity.length - parityFailed.length}'
        ' / ${r.parity.length} pass',
      ),
      for (final x in parityFailed)
        _Line(
          '${x['label']}\n  ${(x['diffs'] as List).join('\n  ')}',
          isOk: false,
        ),
    ];
  }

  static String _ms(int micros) => '${(micros / 1000).toStringAsFixed(2)} ms';

  static String _offset(int minutes) {
    final sign = minutes < 0 ? '-' : '+';
    final m = minutes.abs();
    return '$sign${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  static int _secondsApart(String a, String b) {
    int secs(String t) {
      final p = t.split(':').map(int.tryParse).toList();
      if (p.length != 3 || p.contains(null)) return -100000;
      return p[0]! * 3600 + p[1]! * 60 + p[2]!;
    }

    return (secs(a) - secs(b)).abs();
  }
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
