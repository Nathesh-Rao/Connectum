import 'package:connectum/core/routes/app_pages.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/utils/connect_code.dart';
import 'package:connectum/core/routes/invite_service.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeAuth extends GetxService implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeStore implements SessionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeLinks implements DeepLinkService {
  @override
  final pending = Rxn<ConnectCode>();
  @override
  final showScanHint = false.obs;
  @override
  final isClaimInvalid = false.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeSession extends GetxService implements SessionRepository {
  @override
  Future<void> onInit() async => super.onInit();
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

const _auth = AppRoutes.authentication;
const _home = '/home';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.testMode = false;
  Get.put<AuthRepository>(_FakeAuth());
  Get.put<SessionRepository>(_FakeSession());
  Get.put<ConnectivityService>(
    ConnectivityService()..state.value = AppConnectivity.online,
  );
  Get.put<InviteService>(_FakeInvite());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
  });
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      initialRoute: _auth,
      getPages: [
        AppPages.pages.firstWhere((p) => p.name == AppRoutes.authentication),
        GetPage(
          name: _home,
          page: () => const Scaffold(body: Text('home')),
        ),
      ],
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _tapEmail(WidgetTester tester) async {
  await tester.tap(find.byType(TextField).first);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('login ends on the home route', (tester) async {
    await _pumpApp(tester);
    Get.offAllNamed(_home);
    await _settle(tester);
    expect(Get.currentRoute, _home);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('auth again right after a redirect: tap a field', (tester) async {
    await _pumpApp(tester);
    await _tapEmail(tester);
    Get.offAllNamed(_home);
    await tester.pump(const Duration(milliseconds: 50));
    Get.offAllNamed(_auth);
    await _settle(tester);
    await _tapEmail(tester);
    await tester.enterText(find.byType(TextField).first, 'a@b.co');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth to auth in one step: tap a field', (tester) async {
    await _pumpApp(tester);
    Get.offAllNamed(_auth);
    await _settle(tester);
    await _tapEmail(tester);
    expect(tester.takeException(), isNull);
  });
}
