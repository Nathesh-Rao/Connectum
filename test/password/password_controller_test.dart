import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/models/identity_info.dart';
import 'package:connectum/data/repositories/auth_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/features/password/password_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Auth implements AuthRepository {
  Object? failure;
  String? setOtp;
  String? setPasswordText;
  String? removedOtp;
  String checkMessage = '';
  final checked = <String>[];

  @override
  Future<PasswordCheck> passwordCheck(String password) async {
    checked.add(password);
    return PasswordCheck(isOk: checkMessage.isEmpty, message: checkMessage);
  }

  @override
  Future<LoginStart> startPasswordChange() async {
    if (failure != null) throw failure!;
    return const LoginStart(LoginStartKind.codeSent);
  }

  @override
  Future<void> setPassword(String otp, String newPassword) async {
    if (failure != null) throw failure!;
    setOtp = otp;
    setPasswordText = newPassword;
  }

  @override
  Future<void> removePassword(String otp) async {
    removedOtp = otp;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Store implements SessionStore {
  @override
  final identity = Rxn<IdentityInfo>(
    const IdentityInfo(
      token: 't',
      email: 'a@b.co',
      enterprises: [],
      hasPassword: true,
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<PasswordController> _pump(WidgetTester tester, _Auth auth) async {
  Get.testMode = true;
  final c = PasswordController(auth: auth, store: _Store());
  await tester.pumpWidget(
    GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
  );
  addTearDown(() async {
    c.onClose();
    Get.reset();
  });
  return c;
}

void main() {
  testWidgets('a code is requested, then the fields open', (tester) async {
    final c = await _pump(tester, _Auth());
    expect(c.hasPassword, isTrue);
    await c.sendCode();
    expect(c.isCodeSent.value, isTrue);
    expect(c.info.value, contains('a@b.co'));
  });

  testWidgets('a short password is refused before the request', (tester) async {
    final auth = _Auth();
    final c = await _pump(tester, auth);
    c.code.text = '123456';
    c.newPassword.text = 'short';
    await c.save();
    expect(c.error.value, contains('at least 8'));
    expect(auth.setOtp, isNull);
  });

  testWidgets('a wrong code shows one wording and keeps the fields', (
    tester,
  ) async {
    final auth = _Auth()
      ..failure = const ApiException(
        'otp_invalid',
        'That code is not right.',
        status: 401,
      );
    final c = await _pump(tester, auth);
    c.code.text = '123456';
    c.newPassword.text = 'long enough 1';
    await c.save();
    expect(c.error.value, "That code isn't valid. Request a new one.");
    expect(c.newPassword.text, 'long enough 1');
  });

  testWidgets('a 503 says try again and keeps the code and the password', (
    tester,
  ) async {
    final auth = _Auth()
      ..failure = const ApiException(
        'password_history_unavailable',
        'x',
        status: 503,
      );
    final c = await _pump(tester, auth);
    c.code.text = '123456';
    c.newPassword.text = 'long enough 1';
    await c.save();
    expect(c.error.value, 'Try again in a minute.');
    expect(c.code.text, '123456');
    expect(c.newPassword.text, 'long enough 1');
    auth.failure = null;
    await c.save();
    expect(auth.setOtp, '123456');
  });

  testWidgets('a reused password and a plain 429 have their own words', (
    tester,
  ) async {
    final auth = _Auth()..failure = const ApiException('password_reused', '');
    final c = await _pump(tester, auth);
    c.code.text = '123456';
    c.newPassword.text = 'long enough 1';
    await c.save();
    expect(c.error.value, "You can't reuse a recent password.");
    auth.failure = const ApiException('rate_limited', '', status: 429);
    await c.save();
    expect(
      c.error.value,
      'Too many tries. Please wait a minute and try again.',
    );
  });

  testWidgets('typing asks password/check after a pause and shows its words', (
    tester,
  ) async {
    final auth = _Auth()..checkMessage = 'Choose a stronger password.';
    final c = await _pump(tester, auth);
    c.newPassword.text = 'abc';
    c.passwordChanged();
    await tester.pump(const Duration(milliseconds: 100));
    expect(auth.checked, isEmpty);
    await tester.pump(const Duration(milliseconds: 600));
    expect(auth.checked, ['abc']);
    expect(c.hint.value, 'Choose a stronger password.');
  });

  testWidgets('save sends the code and the new password', (tester) async {
    final auth = _Auth();
    final c = await _pump(tester, auth);
    c.code.text = '123456';
    c.newPassword.text = 'long enough 1';
    expect(c.canSave, isTrue);
    await c.save();
    expect(auth.setOtp, '123456');
    expect(auth.setPasswordText, 'long enough 1');
    expect(c.newPassword.text, isEmpty);
  });
}
