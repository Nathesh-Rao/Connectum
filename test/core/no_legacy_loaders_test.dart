import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _dartFiles(String dir) => [
  for (final f in Directory(dir).listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart')) f,
];

void main() {
  test('nothing in lib or test references loading_circle', () {
    final hits = [
      for (final f in [..._dartFiles('lib'), ..._dartFiles('test')])
        if (!f.path.endsWith('no_legacy_loaders_test.dart') &&
            f.readAsStringSync().contains('loading_circle'))
          f.path,
    ];
    expect(hits, isEmpty);
  });

  test(
    'CupertinoActivityIndicator is used only in AppSpinner and AppRefresh',
    () {
      final hits = [
        for (final f in _dartFiles('lib'))
          if (f.readAsStringSync().contains('CupertinoActivityIndicator') &&
              !f.path.endsWith('app_spinner.dart') &&
              !f.path.endsWith('app_refresh.dart'))
            f.path,
      ];
      expect(hits, isEmpty);
    },
  );

  test('no RefreshIndicator in lib', () {
    final hits = [
      for (final f in _dartFiles('lib'))
        if (RegExp(r'\bRefreshIndicator\(').hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(hits, isEmpty);
  });
}
