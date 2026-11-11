import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/routes/invite_service.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/widgets/app_tab_bar.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/authentication/authentication_controller.dart';
import 'package:connectum/features/authentication/authentication_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeStore implements SessionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeLinks implements DeepLinkService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeSession implements SessionRepository {
  @override
  final loginNotice = RxnString();
  @override
  final loginEmail = RxnString();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeInvite extends InviteService {
  _FakeInvite() : super(_FakeAuth(), _FakeStore(), _FakeLinks());
  @override
  void attach() {}
  @override
  void detach() {}
}

const _labels = AuthenticationController.tabLabels;

class _Errors {
  final errors = <FlutterErrorDetails>[];
  void Function(FlutterErrorDetails)? _previous;

  void start() {
    _previous = FlutterError.onError;
    FlutterError.onError = errors.add;
  }

  void stop() => FlutterError.onError = _previous;

  String get text => errors.map((e) => e.exceptionAsString()).join('\n---\n');
}

Future<AuthenticationController> _pump(
  WidgetTester tester, {
  required Size size,
  double keyboard = 0,
  double textScale = 1,
  bool followsView = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  Get.testMode = true;
  final controller = Get.put(
    AuthenticationController(
      auth: _FakeAuth(),
      session: _FakeSession(),
      connectivity: ConnectivityService()..state.value = AppConnectivity.online,
      invite: _FakeInvite(),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<AuthenticationController>(force: true);
    Get.reset();
  });
  final app = GetMaterialApp(
    theme: AppTheme.light,
    home: const AuthenticationView(),
  );
  await tester.pumpWidget(
    followsView
        ? app
        : MediaQuery(
            data: MediaQueryData(
              size: size,
              viewInsets: EdgeInsets.only(bottom: keyboard),
              textScaler: TextScaler.linear(textScale),
            ),
            child: app,
          ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

Future<void> _tap(WidgetTester tester, int index) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppTabBar),
      matching: find.text(_labels[index]),
    ),
  );
}

Future<void> _play(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump();
}

Future<void> _fill(WidgetTester tester, AuthenticationController c) async {
  c.submitAttempted.value = true;
  c.revision.value++;
  await tester.pump();
}

void main() {
  final sizes = <String, (Size, double, double)>{
    '363.4x745.2': (const Size(363.4, 745.2), 0, 1),
    '360x640': (const Size(360, 640), 0, 1),
    '360x800': (const Size(360, 800), 0, 1),
    '360x800 keyboard 300': (const Size(360, 800), 300, 1),
    '360x640 text scale 1.5': (const Size(360, 640), 0, 1.5),
  };

  for (final entry in sizes.entries) {
    for (final withErrors in [false, true]) {
      testWidgets('tab switches have no layout errors: ${entry.key}'
          '${withErrors ? ', validation errors' : ''}', (tester) async {
        final errors = _Errors()..start();
        addTearDown(errors.stop);
        final (size, keyboard, scale) = entry.value;
        final c = await _pump(
          tester,
          size: size,
          keyboard: keyboard,
          textScale: scale,
        );
        for (final from in [0, 1, 2]) {
          for (final to in [0, 1, 2]) {
            if (from == to) continue;
            await _tap(tester, from);
            await _play(tester);
            if (withErrors) await _fill(tester, c);
            await _tap(tester, to);
            await _play(tester);
            expect(c.mode.value, to);
          }
        }
        expect(errors.text, isEmpty);
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
  }

  testWidgets(
    'rapid tab taps leave no exception',
    (tester) async {
      final errors = _Errors()..start();
      addTearDown(errors.stop);
      final c = await _pump(tester, size: const Size(360, 640));
      for (final index in [1, 0, 2, 1, 0]) {
        await _tap(tester, index);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await _play(tester);
      expect(c.mode.value, 0);
      expect(errors.text, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'typed values survive a tab switch',
    (tester) async {
      final c = await _pump(tester, size: const Size(360, 800));
      await _tap(tester, 1);
      await _play(tester);
      c.orgName.text = 'Acme';
      await _tap(tester, 0);
      await _play(tester);
      await _tap(tester, 1);
      await _play(tester);
      expect(c.orgName.text, 'Acme');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  group('sub-pixel sweep', () {
    double extent(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .maxScrollExtent;

    Future<void> resize(WidgetTester tester, double w, double h) async {
      tester.view.physicalSize = Size(w, h);
      await tester.pump();
    }

    // The viewport height at which the form just fits (no scrolling).
    Future<double> naturalHeight(WidgetTester tester, double w) async {
      var low = 300.0;
      var high = 1600.0;
      for (var i = 0; i < 18; i++) {
        final mid = (low + high) / 2;
        await resize(tester, w, mid);
        if (extent(tester) > 0) {
          low = mid;
        } else {
          high = mid;
        }
      }
      return high;
    }

    for (final width in [363.4, 360.0]) {
      for (var tab = 0; tab < 3; tab++) {
        testWidgets('tab $tab, width $width', (tester) async {
          final errors = _Errors()..start();
          addTearDown(errors.stop);
          final c = await _pump(
            tester,
            size: Size(width, 745.2),
            followsView: true,
          );
          c.selectTab(tab);
          await _play(tester);
          final natural = await naturalHeight(tester, width);
          for (var i = -12; i <= 12; i++) {
            await resize(tester, width, natural + i * 0.25);
          }
          for (final h in [640.0, 745.2, 800.0]) {
            await resize(tester, width, h);
          }
          expect(errors.text, isEmpty);
        }, timeout: const Timeout(Duration(seconds: 30)));
      }
    }

    testWidgets(
      'every tab transition at 363.4x745.2 with keyboard, scale 1.5, errors',
      (tester) async {
        final errors = _Errors()..start();
        addTearDown(errors.stop);
        for (final keyboard in [0.0, 300.0]) {
          final c = await _pump(
            tester,
            size: const Size(363.4, 745.2),
            keyboard: keyboard,
            textScale: 1.5,
          );
          for (final from in [0, 1, 2]) {
            for (final to in [0, 1, 2]) {
              if (from == to) continue;
              c.selectTab(from);
              await _play(tester);
              await _fill(tester, c);
              c.selectTab(to);
              await _play(tester);
              expect(c.mode.value, to);
            }
          }
          for (final index in [1, 2, 0, 1, 0]) {
            c.selectTab(index);
            await tester.pump(const Duration(milliseconds: 40));
          }
          await _play(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await Get.delete<AuthenticationController>(force: true);
        }
        expect(errors.text, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
