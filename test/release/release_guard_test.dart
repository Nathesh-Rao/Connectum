import 'package:flutter_test/flutter_test.dart';
import 'package:connectum/core/routes/app_pages.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/demo/demo_mode.dart';

Set<String> _names(bool isRelease) => {
  for (final p in AppPages.build(isRelease: isRelease)) p.name,
};

void main() {
  const normal = [
    AppRoutes.splash,
    AppRoutes.onboarding,
    AppRoutes.authentication,
    AppRoutes.verification,
    AppRoutes.enterprises,
    AppRoutes.conversation,
    AppRoutes.workspace,
    AppRoutes.profile,
    AppRoutes.form,
    AppRoutes.security,
  ];

  test('release has no /gallery or /debug route and keeps the normal ones', () {
    final names = _names(true);
    expect(
      names.where((n) => n.startsWith('/gallery') || n.startsWith('/debug')),
      isEmpty,
    );
    expect(names, containsAll(normal));
  });

  test('outside release the gallery and debug routes still exist', () {
    final names = _names(false);
    expect(names, containsAll(normal));
    expect(
      names,
      containsAll([
        AppRoutes.gallery,
        AppRoutes.galleryAuth,
        AppRoutes.debugSocket,
        AppRoutes.debugSmartView,
        AppRoutes.debugCrashTest,
        AppRoutes.debugOnboarding,
      ]),
    );
    expect(names.where((n) => n.startsWith('/debug')).length, greaterThan(20));
  });

  test('START_ROUTE is ignored in release and honoured outside it', () {
    expect(
      AppPages.initialFor(isRelease: true, startRoute: '/gallery'),
      AppRoutes.splash,
    );
    expect(
      AppPages.initialFor(isRelease: false, startRoute: '/gallery'),
      '/gallery',
    );
    expect(
      AppPages.initialFor(isRelease: false, startRoute: ''),
      AppRoutes.splash,
    );
  });

  test('DEMO_MODE is ignored in release', () {
    expect(DemoMode.resolve(isRelease: true, requested: true), isFalse);
    expect(DemoMode.resolve(isRelease: false, requested: true), isTrue);
    expect(DemoMode.resolve(isRelease: false, requested: false), isFalse);
  });
}
