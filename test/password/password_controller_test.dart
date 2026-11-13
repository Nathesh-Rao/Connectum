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

  testWidgets('a wrong code shows the server wording and keeps the fields', (
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
    expect(c.error.value, 'That code is not right.');
    expect(c.newPassword.text, 'long enough 1');
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
