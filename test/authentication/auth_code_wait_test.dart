import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/routes/invite_service.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/widgets/app_tab_bar.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/models/auth_flow.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/authentication/authentication_controller.dart';
import 'package:connectum/features/authentication/authentication_view.dart';
import 'package:connectum/features/authentication/code_cooldown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Auth implements AuthRepository {
  ApiException? error;
  @override
  Future<LoginStart> startLogin(String email) async => throw error!;
  @override
  Future<LoginStart> startSetup(Map<String, dynamic> body) async =>
      throw error!;
  @override
  Future<void> startRegister(Map<String, dynamic> body) async => throw error!;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Store implements SessionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Links implements DeepLinkService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Session implements SessionRepository {
  @override
  final loginNotice = RxnString();
  @override
  final loginEmail = RxnString();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Invite extends InviteService {
  _Invite() : super(_Auth(), _Store(), _Links());
  @override
  void attach() {}
  @override
  void detach() {}
}

var _clock = DateTime(2026, 11, 27, 12);

AuthenticationController _controller(_Auth auth) {
  Get.testMode = true;
  return Get.put(
    AuthenticationController(
      auth: auth,
      session: _Session(),
      connectivity: ConnectivityService()..state.value = AppConnectivity.online,
      invite: _Invite(),
    ),
  );
}

void _advance(WidgetTester tester, int seconds) {
  _clock = _clock.add(Duration(seconds: seconds));
}

void main() {
  setUp(() {
    _clock = DateTime(2026, 11, 27, 12);
    CodeCooldown.now = () => _clock;
    CodeCooldown.reset();
  });
  tearDown(() {
    CodeCooldown.now = DateTime.now;
    CodeCooldown.reset();
    Get.reset();
  });

  test('cooldown is kept per action and email, rounds up, then ends', () {
    CodeCooldown.start(AuthFlow.login, 'A@B.co ', 42);
    expect(CodeCooldown.secondsLeft(AuthFlow.login, 'a@b.co'), 42);
    expect(CodeCooldown.secondsLeft(AuthFlow.setup, 'a@b.co'), 0);
    expect(CodeCooldown.secondsLeft(AuthFlow.login, 'x@b.co'), 0);
    _clock = _clock.add(const Duration(milliseconds: 41500));
    expect(CodeCooldown.secondsLeft(AuthFlow.login, 'a@b.co'), 1);
    _clock = _clock.add(const Duration(seconds: 1));
    expect(CodeCooldown.secondsLeft(AuthFlow.login, 'a@b.co'), 0);
  });

  test('words: seconds up to two minutes, then minutes rounded up', () {
    expect(CodeCooldown.sentence(42), 'Try again in 42 s');
    expect(CodeCooldown.sentence(120), 'Try again in 120 s');
    expect(CodeCooldown.sentence(121), 'Try again in 3 min');
  });

  testWidgets('rate_limited disables the button, counts down, re-enables', (
    tester,
  ) async {
    final auth = _Auth()
      ..error = const ApiException(
        'rate_limited',
        '',
        status: 429,
        details: {'retryAfter': 3},
      );
    final c = _controller(auth);
    c.email.text = 'a@b.co';
    await c.submit();
    expect(c.codeWait.value, 3);
    // A second tap does nothing while waiting.
    auth.error = const ApiException('network', '');
    await c.submit();
    expect(c.formError.value, isNull);
    for (final left in [2, 1, 0]) {
      _advance(tester, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(c.codeWait.value, left);
    }
    await c.submit();
    expect(c.formError.value, isNotNull);
    await Get.delete<AuthenticationController>(force: true);
  });

  testWidgets('the wait survives a new controller for the same email', (
    tester,
  ) async {
    final auth = _Auth()
      ..error = const ApiException(
        'rate_limited',
        '',
        details: {'retryAfter': 30},
      );
    var c = _controller(auth);
    c.email.text = 'a@b.co';
    await c.submit();
    await Get.delete<AuthenticationController>(force: true);
    _advance(tester, 10);
    c = _controller(auth);
    c.email.text = 'a@b.co';
    c.changed('email');
    expect(c.codeWait.value, 20);
    c.email.text = 'other@b.co';
    c.changed('email');
    expect(c.codeWait.value, 0);
    // Another action for the same email is not blocked.
    c.email.text = 'a@b.co';
    c.selectTab(1);
    expect(c.codeWait.value, 0);
    c.selectTab(0);
    c.changed('email');
    expect(c.codeWait.value, 20);
    await Get.delete<AuthenticationController>(force: true);
  });

  testWidgets('setup/start names the field and the message lands on it', (
    tester,
  ) async {
    final auth = _Auth()
      ..error = const ApiException(
        'invalid',
        'Enter enterprise name',
        status: 400,
        details: {'field': 'org'},
      );
    final c = _controller(auth);
    c.selectTab(1);
    c.orgName.text = 'Acme';
    c.ownerName.text = 'Ann';
    c.email.text = 'a@b.co';
    c.setupMobile.text = '+919886012345';
    await c.submit();
    expect(c.serverErrors['org'], 'Enter enterprise name');
    expect(c.errorFor('org'), 'Enter enterprise name');

    auth.error = const ApiException(
      'invalid',
      'Enter your name',
      status: 400,
      details: {'field': 'name'},
    );
    await c.submit();
    expect(c.serverErrors['name'], 'Enter your name');
    expect(c.serverErrors.containsKey('org'), isFalse);
  });

  testWidgets('a refused stored address shows the server words and a hint', (
    tester,
  ) async {
    final auth = _Auth()
      ..error = const ApiException(
        'invalid_email',
        'Enter a valid email address.',
        status: 400,
      );
    final c = _controller(auth);
    c.email.text = 'a@b.co';
    await c.submit();
    expect(
      c.serverErrors['email'],
      'Enter a valid email address. Correct the address before a code can be sent.',
    );
  });

  testWidgets('tabs read Sign in | Register | New Org, Sign in first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = _controller(_Auth());
    await tester.pumpWidget(
      GetMaterialApp(theme: AppTheme.light, home: const AuthenticationView()),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final bar = tester.widget<AppTabBar>(find.byType(AppTabBar));
    expect(bar.labels, ['Sign in', 'Register', 'New Org']);
    expect(bar.selectedIndex, 0);
    expect(find.text('Self register'), findsNothing);
    expect(find.text('Set up'), findsNothing);
    expect(find.textContaining('YOUR ACCOUNT'), findsNothing);
    expect(find.textContaining('Private by design'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(AppTabBar),
        matching: find.text('New Org'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.mode.value, 1);
    expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).selectedIndex, 2);

    await tester.tap(
      find.descendant(
        of: find.byType(AppTabBar),
        matching: find.text('Register'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.mode.value, 2);
    expect(tester.widget<AppTabBar>(find.byType(AppTabBar)).selectedIndex, 1);
  });
}
