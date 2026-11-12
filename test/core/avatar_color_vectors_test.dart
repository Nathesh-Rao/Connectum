import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/design_guide/avatar_vectors.dart';

void main() {
  testWidgets('design-guide avatar vectors match the real code', (
    tester,
  ) async {
    final file = File('design-guide-mobile/tokens/avatar-color-vectors.json');
    final stored = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final actual =
        jsonDecode(jsonEncode(await buildAvatarVectors(tester)))
            as Map<String, Object?>;
    for (final key in actual.keys) {
      expect(
        stored[key],
        equals(actual[key]),
        reason:
            '$key drifted: run flutter test tool/design_guide/generate.dart',
      );
    }
  });
}
