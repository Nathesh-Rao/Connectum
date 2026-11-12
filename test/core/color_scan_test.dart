import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

List<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _code(File f) =>
    f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

Map<String, List<String>> _allowlist() {
  final out = <String, List<String>>{};
  for (final line in File('test/core/color_allowlist.txt').readAsLinesSync()) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final p = line.split('|');
    expect(p.length, 3, reason: 'allowlist line needs a reason: $line');
    expect(p[2].trim(), isNotEmpty);
    out.putIfAbsent(p[0], () => []).add(p[1]);
  }
  return out;
}

void main() {
  final hexLiteral = RegExp(
    r'Color\(\s*0x[0-9A-Fa-f]{8}\s*\)|#[0-9A-Fa-f]{6}\b',
  );

  test('no hard-coded colour in features or core widgets', () {
    final allowed = _allowlist()['hard-coded'] ?? [];
    final bad = <String>[];
    for (final dir in ['lib/features', 'lib/core/widgets']) {
      for (final f in _dart(dir)) {
        if (allowed.contains(f.path)) continue;
        if (hexLiteral.hasMatch(_code(f))) bad.add(f.path);
      }
    }
    expect(bad, isEmpty, reason: 'move these into the colour tokens');
  });

  test('nothing in lib is called orange, peach or coral', () {
    final name = RegExp(r'orange|peach|coral', caseSensitive: false);
    final bad = <String>[];
    for (final f in _dart('lib')) {
      if (name.hasMatch(_code(f))) bad.add(f.path);
    }
    expect(bad, isEmpty);
  });

  test('no colour literal in lib sits between 10 and 55 degrees', () {
    final allowed = _allowlist()['warm-hue'] ?? [];
    final literal = RegExp(r'0x([0-9A-Fa-f]{2})([0-9A-Fa-f]{6})\b');
    final bad = <String>[];
    for (final f in _dart('lib')) {
      if (allowed.contains(f.path)) continue;
      final code = _code(f);
      for (final m in literal.allMatches(code)) {
        if (m[2]!.length != 6) continue;
        final c = Color(int.parse('FF${m[2]}', radix: 16));
        final hsl = HSLColor.fromColor(c);
        if (hsl.hue >= 10 && hsl.hue <= 55 && hsl.saturation > 0.25) {
          bad.add('${f.path}: 0x${m[1]}${m[2]}');
        }
      }
    }
    expect(bad, isEmpty);
  });
}
