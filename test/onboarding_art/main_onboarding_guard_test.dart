import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

List<String> _imports(File f) => RegExp(
  r'''^import\s+['"]([^'"]+)['"]''',
  multiLine: true,
).allMatches(f.readAsStringSync()).map((m) => m[1]!).toList();

void main() {
  test(
    'the main onboarding imports only the public stage, never debug code',
    () {
      final files = [
        ..._dart('lib/features/onboarding'),
        File('lib/core/widgets/onboarding_art_stage.dart'),
      ];
      for (final f in files) {
        for (final i in _imports(f)) {
          expect(i.contains('debug_'), isFalse, reason: '${f.path} imports $i');
          if (i.contains('onboarding_art/')) {
            expect(
              i.endsWith('onboarding_art/onboarding_art.dart'),
              isTrue,
              reason: '${f.path} imports $i (only the public widget)',
            );
          }
        }
      }
      final view = File('lib/features/onboarding/onboarding_view.dart');
      expect(
        _imports(
          view,
        ).any((i) => i.endsWith('widgets/onboarding_art_stage.dart')),
        isTrue,
      );
    },
  );

  test('no release code imports a debug_* feature folder', () {
    const allowed = {'lib/core/routes/app_pages.dart'};
    for (final f in _dart('lib')) {
      final path = f.path;
      if (allowed.contains(path) ||
          path.startsWith('lib/features/debug_') ||
          path.startsWith('lib/core/debug/') ||
          path.startsWith('lib/demo/')) {
        continue;
      }
      for (final i in _imports(f)) {
        expect(
          i.contains('features/debug_') || i.contains('/debug_'),
          isFalse,
          reason: '$path imports $i',
        );
      }
    }
  });

  test('the retired Lottie widgets are not used any more', () {
    for (final f in _dart('lib')) {
      final code = f.readAsStringSync();
      expect(code.contains('OnboardingLottie'), isFalse, reason: f.path);
      expect(code.contains('onboarding_lottie'), isFalse, reason: f.path);
    }
  });

  test('onboarding_art does not import the main onboarding', () {
    for (final f in _dart('lib/core/widgets/onboarding_art')) {
      final code = f.readAsStringSync();
      expect(code.contains('features/onboarding'), isFalse, reason: f.path);
    }
  });
}
