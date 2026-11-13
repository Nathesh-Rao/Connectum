import 'package:connectum/core/widgets/onboarding_art/onboarding_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: SizedBox(width: 400, height: 300, child: child),
  ),
);

OnboardingArtState _state(WidgetTester t) =>
    t.state<OnboardingArtState>(find.byType(OnboardingArt));

const _tick = Duration(milliseconds: 100);

void main() {
  testWidgets('starts a ticker and time advances', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _host(OnboardingArt(kind: OnboardingArtKind.shield, controller: c)),
    );
    await tester.pump(_tick);
    await tester.pump(_tick);
    expect(_state(tester).isTicking, isTrue);
    expect(c.time.value, greaterThan(0));
  });

  testWidgets('stops when not the active page and resumes when active', (
    tester,
  ) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    Widget app(bool active) => _host(
      OnboardingArt(
        kind: OnboardingArtKind.network,
        controller: c,
        isActive: active,
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump(_tick);
    await tester.pump(_tick);
    await tester.pumpWidget(app(false));
    final frozen = c.time.value;
    expect(_state(tester).isTicking, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(c.time.value, frozen);
    await tester.pumpWidget(app(true));
    await tester.pump(_tick);
    await tester.pump(_tick);
    expect(_state(tester).isTicking, isTrue);
    expect(c.time.value, greaterThan(frozen));
  });

  testWidgets('stops when the app is paused and resumes', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _host(OnboardingArt(kind: OnboardingArtKind.buildings, controller: c)),
    );
    await tester.pump(_tick);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(_state(tester).isTicking, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_tick);
    await tester.pump(_tick);
    expect(_state(tester).isTicking, isTrue);
  });

  testWidgets('does not advance while its route is covered (TickerMode off)', (
    tester,
  ) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _host(
        TickerMode(
          enabled: false,
          child: OnboardingArt(kind: OnboardingArtKind.shield, controller: c),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(c.time.value, 0);
  });

  testWidgets('disposes cleanly with no ticker left', (tester) async {
    await tester.pumpWidget(
      _host(const OnboardingArt(kind: OnboardingArtKind.shield)),
    );
    await tester.pump(_tick);
    await tester.pumpWidget(_host(const SizedBox()));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows the static frame and creates no ticker', (
    tester,
  ) async {
    for (final kind in OnboardingArtKind.values) {
      final c = OnboardingArtController();
      await tester.pumpWidget(
        _host(OnboardingArt(kind: kind, controller: c, reducedMotion: true)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).hasTicker, isFalse, reason: kind.name);
      expect(c.time.value, greaterThan(1.9), reason: kind.name);
      if (kind == OnboardingArtKind.shield) expect(c.time.value, 1.95);
      await tester.pumpWidget(_host(const SizedBox()));
      c.dispose();
    }
  });

  testWidgets('the platform disable-animations flag also means reduced', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 400,
            height: 300,
            child: const OnboardingArt(kind: OnboardingArtKind.shield),
          ),
        ),
      ),
    );
    expect(_state(tester).hasTicker, isFalse);
  });

  testWidgets('replay restarts the intro at t=0; seek pauses; pause holds', (
    tester,
  ) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _host(OnboardingArt(kind: OnboardingArtKind.shield, controller: c)),
    );
    await tester.pump(_tick);
    c.seek(5);
    await tester.pump(_tick);
    expect(_state(tester).isTicking, isFalse);
    expect(c.time.value, 5);
    c.play();
    expect(c.time.value, 0);
    await tester.pump(_tick);
    await tester.pump(_tick);
    expect(_state(tester).isTicking, isTrue);
    c.pause();
    final held = c.time.value;
    await tester.pump(const Duration(seconds: 1));
    expect(c.time.value, held);
  });

  testWidgets('speed scales the time', (tester) async {
    final c = OnboardingArtController()..speed = 0.25;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _host(OnboardingArt(kind: OnboardingArtKind.shield, controller: c)),
    );
    await tester.pump(_tick);
    await tester.pump(const Duration(milliseconds: 80));
    expect(c.time.value, lessThan(0.05));
    expect(c.time.value, greaterThan(0));
  });

  testWidgets('without loop it stops at the end', (tester) async {
    final c = OnboardingArtController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      _host(
        OnboardingArt(kind: OnboardingArtKind.shield, controller: c, loop: false),
      ),
    );
    c.time.value = c.duration - 0.05;
    await tester.pump(_tick);
    await tester.pump(_tick);
    await tester.pump(_tick);
    expect(c.time.value, c.duration);
    expect(c.isPlaying, isFalse);
  });

  testWidgets('the blue-only switch rebuilds the scene without an error', (
    tester,
  ) async {
    Widget app(bool blue) => _host(
      OnboardingArt(kind: OnboardingArtKind.shield, blueOnly: blue),
    );
    await tester.pumpWidget(app(false));
    await tester.pump(_tick);
    await tester.pumpWidget(app(true));
    await tester.pump(_tick);
    expect(tester.takeException(), isNull);
  });
}
