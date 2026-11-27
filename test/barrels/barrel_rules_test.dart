import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _exportLine = RegExp(r"^export '[^']+\.dart';$");

List<File> _barrels() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where(
      (f) => f.readAsLinesSync().firstOrNull?.startsWith('// Barrel:') ?? false,
    )
    .toList();

void main() {
  test('barrels contain a header, then sorted export lines only', () {
    final barrels = _barrels();
    expect(barrels, isNotEmpty);
    for (final file in barrels) {
      final lines = file.readAsLinesSync();
      final body = lines.skip(1).where((l) => l.trim().isNotEmpty).toList();
      expect(body, isNotEmpty, reason: '${file.path} exports nothing');
      for (final line in body) {
        expect(
          _exportLine.hasMatch(line),
          isTrue,
          reason: '${file.path}: not an export line: $line',
        );
      }
      expect(
        body,
        [...body]..sort(),
        reason: '${file.path}: exports not sorted',
      );
    }
  });

  test('files never import the barrel of their own folder or feature', () {
    for (final barrel in _barrels()) {
      final dir = barrel.parent.path;
      final name = barrel.uri.pathSegments.last;
      final package = 'package:connectum/${barrel.path.substring(4)}';
      for (final f
          in Directory(dir)
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (f) => f.path.endsWith('.dart') && f.path != barrel.path,
              )) {
        final text = f.readAsStringSync();
        expect(
          text.contains("'$package'"),
          isFalse,
          reason: '${f.path} imports its own barrel',
        );
        expect(
          RegExp("import '(\\.\\./)*\\.?/?$name'").hasMatch(text),
          isFalse,
          reason: '${f.path} imports its own barrel',
        );
      }
    }
  });
}
