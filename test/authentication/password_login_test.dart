import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/routes/deep_link_service.dart';
import 'package:connectum/core/routes/invite_service.dart';
import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/api/api_messages.dart';
import 'package:connectum/data/models/identity_info.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/repositories/session_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/features/authentication/authentication_controller.dart';
import 'package:connectum/features/authentication/authentication_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _secret = 'S3cret-Pass-9';
const _token = 'tok-should-never-be-logged';

class _Auth implements AuthRepository {
  Object? failure;
  Object? startLoginResult;
  int calls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<IdentityInfo> loginWithPassword(String email, String password) async {
    calls++;
    lastEmail = email;
    lastPassword = password;
    if (failure != null) throw failure!;
    return const IdentityInfo(token: _token, email: 'a@b.co', enterprises: []);
  }

  @override
  Future<LoginStart> startLogin(String email) async =>
      const LoginStart(LoginStartKind.trusted);

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
  WidgetTester tester,
  _Auth auth, {
  Size size = const Size(363, 745),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.testMode = true;
  final controller = Get.put(
    AuthenticationController(
      auth: auth,
      session: _Session(),
      connectivity: ConnectivityService()..state.value = AppConnectivity.online,
      invite: _Invite(),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<AuthenticationController>(force: true);
    Get.reset();
  });
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light,
      home: const AuthenticationView(),
      getPages: [
        GetPage(
          name: AppRoutes.enterprises,
          page: () => const Scaffold(body: Text('enterprises')),
        ),
      ],
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

Finder _methodButton(String label) => find.bySemanticsLabel(label);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _usePassword(WidgetTester tester) async {
  await tester.tap(find.text('Sign in with password'));
  await _settle(tester);
}

Future<void> _signIn(AuthenticationController c, WidgetTester tester) async {
  c.email.text = 'a@b.co';
  c.password.text = _secret;
  await c.submit();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('defaults to the email code with the key button', (tester) async {
    final c = await _pump(tester, _Auth());
    expect(c.isPasswordMode.value, isFalse);
    expect(find.text('Sign in with password'), findsOneWidget);
    expect(find.byIcon(Icons.vpn_key_outlined), findsOneWidget);
    expect(find.text('Your password'), findsNothing);
    expect(find.text('Email code'), findsNothing);
    expect(find.text('A secure code. No password to remember.'), findsNothing);
    expect(_methodButton('Sign in with password'), findsOneWidget);
  });

  testWidgets('the button shows the password field and offers the code', (
    tester,
  ) async {
    final c = await _pump(tester, _Auth());
    await _usePassword(tester);
    expect(c.isPasswordMode.value, isTrue);
    expect(find.text('Your password'), findsOneWidget);
    expect(find.text('Sign in with email code'), findsOneWidget);
    expect(find.byIcon(Icons.mail_outline), findsWidgets);
    expect(find.text('Sign in with password'), findsNothing);
    expect(find.byIcon(Icons.vpn_key_outlined), findsNothing);
    expect(_methodButton('Sign in with email code'), findsOneWidget);
  });

  testWidgets('switching keeps the email, clears password and errors', (
    tester,
  ) async {
    final auth = _Auth()
      ..failure = const ApiException('invalid_credentials', '', status: 401);
    final c = await _pump(tester, auth);
    await _usePassword(tester);
    await _signIn(c, tester);
    expect(c.formError.value, ApiMessages.wrongPassword);
    expect(find.text('Use email code instead'), findsNothing);
    c.password.text = 'abc';
    await tester.ensureVisible(find.text('Sign in with email code'));
    await tester.pump();
    await tester.tap(find.text('Sign in with email code'));
    await _settle(tester);
    expect(c.isPasswordMode.value, isFalse);
    expect(c.email.text, 'a@b.co');
    expect(c.password.text, isEmpty);
    expect(c.formError.value, isNull);
    expect(c.errorFor('password'), isNull);
    expect(find.text('Your password'), findsNothing);
  });

  testWidgets('focus goes to the password, or to the email when empty', (
    tester,
  ) async {
    final c = await _pump(tester, _Auth());
    await _usePassword(tester);
    expect(c.focus['email']!.hasFocus, isTrue);
    c.setPasswordMode(false);
    c.email.text = 'a@b.co';
    await _settle(tester);
    await tester.tap(find.text('Sign in with password'));
    await _settle(tester);
    expect(c.focus['password']!.hasFocus, isTrue);
  });

  testWidgets('reduced motion: the method button switches without a fade', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, _Auth());
    final switcher = tester.widget<AnimatedSwitcher>(
      find.ancestor(
        of: find.text('Sign in with password'),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets('autofill hints, no suggestions, and the eye toggle', (
    tester,
  ) async {
    await _pump(tester, _Auth());
    await _usePassword(tester);
    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .toList();
    final password = fields.firstWhere(
      (f) => f.autofillHints?.contains(AutofillHints.password) ?? false,
    );
    final email = fields.firstWhere(
      (f) => f.autofillHints?.contains(AutofillHints.username) ?? false,
    );
    expect(email.autofillHints, contains(AutofillHints.email));
    expect(password.obscureText, isTrue);
    expect(password.autocorrect, isFalse);
    expect(password.enableSuggestions, isFalse);
    expect(find.byType(AutofillGroup), findsWidgets);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    final shown = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .firstWhere(
          (f) => f.autofillHints?.contains(AutofillHints.password) ?? false,
        );
    expect(shown.obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('success ends where the code sign-in ends', (tester) async {
    final auth = _Auth();
    final c = await _pump(tester, auth);
    await c.auth.startLogin('a@b.co');
    Get.offAllNamed(AppRoutes.enterprises); // what the trusted code path does
    await tester.pump(const Duration(milliseconds: 400));
    final afterCode = Get.currentRoute;
    Get.offAllNamed('/');
    await tester.pump(const Duration(milliseconds: 400));
    c.setPasswordMode(true);
    await _signIn(c, tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(auth.lastEmail, 'a@b.co');
    expect(auth.lastPassword, _secret);
    expect(Get.currentRoute, afterCode);
    expect(c.password.text, isEmpty);
  });

  testWidgets('wrong password: one message, password cleared, email kept', (
    tester,
  ) async {
    final auth = _Auth()
      ..failure = const ApiException('invalid_credentials', '', status: 401);
    final c = await _pump(tester, auth);
    c.setPasswordMode(true);
    await _signIn(c, tester);
    expect(c.formError.value, ApiMessages.wrongPassword);
    expect(c.password.text, isEmpty);
    expect(c.email.text, 'a@b.co');
    expect(c.errorFor('password'), isNull);
    await tester.pump();
    expect(find.text('Use email code instead'), findsNothing);
    await tester.tap(find.text('Sign in with email code'));
    await tester.pump();
    expect(c.isPasswordMode.value, isFalse);
    expect(c.email.text, 'a@b.co');
  });

  testWidgets('locked: message, and a countdown when the server gives one', (
    tester,
  ) async {
    final auth = _Auth()
      ..failure = const ApiException(
        'rate_limited',
        '',
        status: 429,
        details: {'retryAfter': 3},
      );
    final c = await _pump(tester, auth);
    c.setPasswordMode(true);
    await _signIn(c, tester);
    expect(c.formError.value, ApiMessages.passwordLocked);
    expect(c.retryIn.value, 3);
    await tester.pump();
    expect(find.text('Try again in 3s'), findsOneWidget);
    await c.submit();
    expect(auth.calls, 1); // ignored while waiting
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(c.retryIn.value, 0);
    await tester.pump();
    expect(find.text('Sign in'), findsWidgets);
    expect(find.textContaining('Try again in'), findsNothing);
  });

  testWidgets('locked without a time: message only, button stays', (
    tester,
  ) async {
    final auth = _Auth()
      ..failure = const ApiException('rate_limited', '', status: 429);
    final c = await _pump(tester, auth);
    c.setPasswordMode(true);
    await _signIn(c, tester);
    expect(c.formError.value, ApiMessages.passwordLocked);
    expect(c.retryIn.value, 0);
  });

  testWidgets('network error keeps the whole form', (tester) async {
    final auth = _Auth()..failure = const ApiException('network', '');
    final c = await _pump(tester, auth);
    c.setPasswordMode(true);
    await _signIn(c, tester);
    expect(c.formError.value, contains("Can't reach the server"));
    expect(c.password.text, _secret);
    expect(c.email.text, 'a@b.co');
  });

  testWidgets('an empty password is stopped before the request', (
    tester,
  ) async {
    final auth = _Auth();
    final c = await _pump(tester, auth);
    c.setPasswordMode(true);
    c.email.text = 'a@b.co';
    await c.submit();
    expect(auth.calls, 0);
    expect(c.errorFor('password'), 'Enter your password.');
  });

  testWidgets('the password and the token are never logged', (tester) async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    final auth = _Auth();
    final c = await _pump(tester, auth);
    c.setPasswordMode(true);
    await _signIn(c, tester);
    auth.failure = const ApiException('invalid_credentials', '');
    await _signIn(c, tester);
    debugPrint = previous;
    final all = logs.join('\n');
    expect(all.contains(_secret), isFalse);
    expect(all.contains(_token), isFalse);
  });

  for (final size in [const Size(363, 745), const Size(412, 915)]) {
    testWidgets('no overflow in code mode at $size', (tester) async {
      final errors = _Errors()..start();
      addTearDown(errors.stop);
      await _pump(tester, _Auth(), size: size);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sign in with password'), findsOneWidget);
      expect(errors.text, isEmpty);
    });

    testWidgets('no overflow in password mode at $size', (tester) async {
      final errors = _Errors()..start();
      addTearDown(errors.stop);
      final auth = _Auth()
        ..failure = const ApiException('invalid_credentials', '');
      final c = await _pump(tester, auth, size: size);
      await _usePassword(tester);
      await _signIn(c, tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sign in with email code'), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      c.selectTab(1);
      await tester.pump(const Duration(milliseconds: 400));
      c.selectTab(0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(errors.text, isEmpty);
    });
  }
}
