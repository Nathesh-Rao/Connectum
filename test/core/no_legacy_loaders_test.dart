import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no RefreshIndicator or CupertinoActivityIndicator in lib', () {
    final hits = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      if (RegExp(
        r'\bRefreshIndicator\(|CupertinoActivityIndicator',
      ).hasMatch(text)) {
        hits.add(file.path);
      }
    }
    expect(hits, isEmpty);
  });
}
