import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refresh controls are built only in AppRefresh', () {
    final allowed = {
      'lib/core/widgets/app_refresh.dart',
      for (final line in File(
        'test/core/raw_refresh_allowlist.txt',
      ).readAsLinesSync())
        if (line.trim().isNotEmpty && !line.startsWith('#'))
          line.split('|').first.trim(),
    };
    final pattern = RegExp(
      r'\bRefreshIndicator\b|CupertinoSliverRefreshControl|CupertinoActivityIndicator',
    );
    final hits = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !allowed.contains(f.path) &&
            !f.path.endsWith('app_spinner.dart') &&
            pattern.hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(hits, isEmpty);
  });
}
