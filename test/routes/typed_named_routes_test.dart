import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `Get.toNamed<T>` casts GetX's `GetPageRoute<dynamic>` to `Route<T>`, which
/// throws for any T other than dynamic. Named routes are called untyped and
/// the result is checked with `is`.
const _allowed = <String, String>{
  // 'lib/path.dart': 'reason',
};

void main() {
  test('no typed Get.toNamed / offNamed / offAllNamed in lib/', () {
    final pattern = RegExp(
      r'Get\.(toNamed|offNamed|offAllNamed|offAndToNamed)\s*<',
    );
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (_allowed.containsKey(f.path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) found.add('${f.path}:${i + 1}');
      }
    }
    expect(found, isEmpty, reason: 'typed named-route calls: $found');
  });
}
