import 'dart:convert';
import 'dart:io';

import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/routes/invite_service.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/widgets/app_ambient_backdrop.dart';
import 'package:connectum/core/widgets/app_scaffold.dart';
import 'package:connectum/core/widgets/app_state_image.dart';
import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/core/widgets/app_success_animation.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/ai_agents/ai_agents_controller.dart';
import 'package:connectum/features/ai_agents/ai_agents_view.dart';
import 'package:connectum/features/authentication/authentication_controller.dart';
import 'package:connectum/features/authentication/authentication_view.dart';
import 'package:connectum/features/onboarding/onboarding_controller.dart';
import 'package:connectum/features/onboarding/onboarding_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Future<void> _loadFonts() async {
  final loader = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
    );
  }
  await loader.load();
  final display = FontLoader('SpaceGrotesk');
  for (final w in ['SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/SpaceGrotesk-$w.ttf').readAsBytesSync();
    display.addFont(
      Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
    );
  }
  await display.load();
}

/// Hue in degrees and saturation of an RGB colour held as 0..1 floats.
bool _isWarm(List<num> rgb) {
  final c = Color.from(
    alpha: 1,
    red: rgb[0].toDouble().clamp(0, 1),
    green: rgb[1].toDouble().clamp(0, 1),
    blue: rgb[2].toDouble().clamp(0, 1),
  );
  final hsl = HSLColor.fromColor(c);
  return hsl.hue >= 10 && hsl.hue <= 55 && hsl.saturation > 0.25;
}

/// Every solid and gradient colour a Lottie file paints.
List<List<num>> _lottieColors(Object? node) {
  final out = <List<num>>[];
  void stops(List<dynamic> v, int count) {
    for (var i = 0; i < count && i * 4 + 3 < v.length; i++) {
      out.add(v.sublist(i * 4 + 1, i * 4 + 4).cast<num>());
    }
  }

  void walk(Object? n) {
    if (n is Map) {
      final type = n['ty'];
      if ((type == 'fl' || type == 'st') && n['c'] is Map) {
        final k = (n['c'] as Map)['k'];
        if (k is List && k.isNotEmpty && k.first is num) {
          out.add(k.take(3).cast<num>().toList());
        } else if (k is List) {
          for (final kf in k) {
            if (kf is Map && kf['s'] is List) {
              out.add((kf['s'] as List).take(3).cast<num>().toList());
            }
          }
        }
      }
      if ((type == 'gf' || type == 'gs') && n['g'] is Map) {
        final g = n['g'] as Map;
        final k = (g['k'] as Map)['k'];
        if (k is List && k.isNotEmpty && k.first is num) {
          stops(k, g['p'] as int);
        } else if (k is List) {
          for (final kf in k) {
            if (kf is Map && kf['s'] is List) {
              stops(kf['s'] as List, g['p'] as int);
            }
          }
        }
      }
      n.values.forEach(walk);
    } else if (n is List) {
      n.forEach(walk);
    }
  }

  walk(node);
  return out;
}

const _sizes = <String, Size>{
  '363x745': Size(363.4, 745.2),
  '412x915': Size(412, 915),
};

/// Real time for the asset bundle, then fixed frames.
Future<void> _settle(WidgetTester tester, int frames) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(_loadFonts);

  group('Lottie files on the decorative screens', () {
    final dir = Directory('assets/lottie');
    final loaded = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.json'))
        .toList();

    test('every Lottie the code loads has no warm colour', () {
      final names = RegExp(r"assets/lottie/[\w${}.]+\.json");
      final used = <String>{};
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in names.allMatches(f.readAsStringSync())) {
          used.add(m[0]!);
        }
      }
      expect(used, isNotEmpty);
      for (final path in loaded) {
        final name = path.split('/').last;
        if (!used.any((u) => u.endsWith(name))) continue;
        final warm = _lottieColors(
          jsonDecode(File(path).readAsStringSync()),
        ).where(_isWarm).length;
        expect(warm, 0, reason: '$name still has $warm warm colours');
      }
    });

    List<List<num>> blueColors(String name) => _lottieColors(
      jsonDecode(File('assets/lottie/${name}_blue.json').readAsStringSync()),
    );

    test('the loading copies still hold violet and purple', () {
      bool has(List<List<num>> colors, int r, int g, int b) => colors.any(
        (c) =>
            (c[0] * 255 - r).abs() < 2 &&
            (c[1] * 255 - g).abs() < 2 &&
            (c[2] * 255 - b).abs() < 2,
      );
      for (final name in ['loading', 'qr_loading']) {
        final colors = blueColors(name);
        expect(has(colors, 0x8B, 0x5C, 0xF6), isTrue, reason: '$name violet');
        expect(has(colors, 0x6A, 0x3F, 0xD4), isTrue, reason: '$name purple');
      }
    });

    test('the onboarding copies have no violet, purple or warm colour', () {
      for (final name in [
        'onboarding_enterprises',
        'onboarding_network',
        'onboarding_security',
      ]) {
        final colors = blueColors(name);
        expect(colors, isNotEmpty);
        final violet = colors.where((c) {
          final hsl = HSLColor.fromColor(
            Color.from(
              alpha: 1,
              red: c[0].toDouble().clamp(0, 1),
              green: c[1].toDouble().clamp(0, 1),
              blue: c[2].toDouble().clamp(0, 1),
            ),
          );
          return hsl.hue >= 245 && hsl.hue <= 330 && hsl.saturation > 0.1;
        });
        expect(violet, isEmpty, reason: '$name has violet or purple');
        expect(colors.where(_isWarm), isEmpty, reason: '$name has warm');
      }
    });

    test('the code loads the _blue copies of the onboarding files', () {
      final lottie = File(
        'lib/core/widgets/onboarding_lottie.dart',
      ).readAsStringSync();
      expect(lottie, contains("_blue.json"));
    });
  });

  group('goldens', () {
    Future<void> shoot(
      WidgetTester tester,
      String name,
      String size,
      Widget app, {
      int frames = 40,
    }) async {
      tester.view.physicalSize = _sizes[size]!;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(key: const Key('shot'), child: app),
      );
      await _settle(tester, frames);
      await expectLater(
        find.byKey(const Key('shot')),
        matchesGoldenFile('goldens/decor_${name}_$size.png'),
      );
    }

    for (final size in _sizes.keys) {
      for (var slide = 0; slide < 3; slide++) {
        testWidgets('onboarding slide ${slide + 1} at $size', (tester) async {
          Get.testMode = true;
          final c = Get.put(
            OnboardingController(
              store: _FakeStore(),
              isReplay: false,
              invite: _FakeInvite(),
            ),
          );
          addTearDown(Get.reset);
          tester.view.physicalSize = _sizes[size]!;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('shot'),
              child: GetMaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                home: const OnboardingView(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
          c.pageController.jumpToPage(slide);
          await tester.pump();
          await _settle(tester, 80);
          await expectLater(
            find.byKey(const Key('shot')),
            matchesGoldenFile(
              'goldens/decor_onboarding_${slide + 1}_$size.png',
            ),
          );
        });
      }

      testWidgets('authentication at $size', (tester) async {
        Get.testMode = true;
        Get.put(
          AuthenticationController(
            auth: _FakeAuth(),
            session: _FakeSession(),
            connectivity: ConnectivityService()
              ..state.value = AppConnectivity.online,
            invite: _FakeInvite(),
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          Get.reset();
        });
        await shoot(
          tester,
          'authentication',
          size,
          GetMaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const AuthenticationView(),
          ),
          frames: 20,
        );
      });

      testWidgets('agents launching soon at $size', (tester) async {
        Get.testMode = true;
        Get.put(AiAgentsController());
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          Get.reset();
        });
        await shoot(
          tester,
          'agents',
          size,
          GetMaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const AiAgentsView(),
          ),
          frames: 20,
        );
      });

      testWidgets('ambient splash and access at $size', (tester) async {
        await shoot(
          tester,
          'ambient',
          size,
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const Row(
              children: [
                Expanded(
                  child: AppScaffold(
                    ambient: AppAmbientVariant.splash,
                    body: SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: AppScaffold(
                    ambient: AppAmbientVariant.access,
                    body: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
          frames: 2,
        );
      });

      testWidgets('empty state and success at $size', (tester) async {
        await shoot(
          tester,
          'states',
          size,
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: AppStateView(
                      state: AppViewState.empty,
                      emptyImage: AppStateImageKind.emptyChats,
                      emptyTitle: 'No chats yet',
                      child: SizedBox.shrink(),
                    ),
                  ),
                  Expanded(child: Center(child: AppSuccessAnimation())),
                ],
              ),
            ),
          ),
          frames: 60,
        );
      });
    }
  });
}
