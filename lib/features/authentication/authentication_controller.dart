import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/socket/connectivity_service.dart';

class AuthenticationController extends GetxController {
  AuthenticationController({
    required this.auth,
    required this.session,
    required this.connectivity,
  });

  static final _emailPattern = RegExp(r'^\S+@\S+\.\S+$');

  final AuthRepository auth;
  final SessionRepository session;
  final ConnectivityService connectivity;

  final email = TextEditingController();
  final username = TextEditingController();
  final mobile = TextEditingController();
  final country = TextEditingController();
  final city = TextEditingController();

  /// 0 = Sign in, 1 = Create account.
  final mode = 0.obs;
  final isBusy = false.obs;
  final formError = RxnString();
  final fieldErrors = <String, String>{}.obs;

  List<String> _countries = [];

  bool get isRegister => mode.value == 1;
  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  void setMode(int value) {
    mode.value = value;
    formError.value = null;
    fieldErrors.clear();
  }

  void dismissNotice() => session.loginNotice.value = null;

  void _clearErrors() {
    formError.value = null;
    fieldErrors.clear();
  }

  Future<void> submit() async {
    if (isBusy.value) return;
    _clearErrors();
    final emailText = email.text.trim();
    if (!_emailPattern.hasMatch(emailText)) {
      fieldErrors['email'] = 'Enter a valid email address.';
      return;
    }
    if (isRegister && username.text.trim().isEmpty) {
      fieldErrors['username'] = 'Choose a username.';
      return;
    }
    isBusy.value = true;
    try {
      if (isRegister) {
        await auth.startRegister(_registerBody(emailText));
        _openVerification(emailText, retryAfter: 30);
      } else {
        final result = await auth.startLogin(emailText);
        switch (result.kind) {
          case LoginStartKind.trusted:
            Get.offAllNamed(AppRoutes.enterprises);
          case LoginStartKind.throttled:
            _openVerification(emailText, retryAfter: result.retryAfter);
          case LoginStartKind.codeSent:
            _openVerification(emailText, retryAfter: 30);
        }
      }
    } on UnsupportedStep catch (e) {
      formError.value =
          "This account needs a step the mobile app doesn't support yet (${e.reasons.join(', ')}).";
    } on ApiException catch (e) {
      final fields = e.fieldErrors;
      if (fields.isNotEmpty) {
        fieldErrors.assignAll(fields);
      } else {
        formError.value = ApiMessages.of(e);
      }
    } finally {
      isBusy.value = false;
    }
  }

  Map<String, dynamic> _registerBody(String emailText) => {
    'username': username.text.trim(),
    'email': emailText,
    if (mobile.text.trim().isNotEmpty) 'mobile': mobile.text.trim(),
    if (country.text.isNotEmpty) 'country': country.text,
    if (city.text.isNotEmpty) 'city': city.text,
  };

  void _openVerification(String emailText, {required int retryAfter}) {
    Get.toNamed(
      AppRoutes.verification,
      arguments: {
        'email': emailText,
        'isRegister': isRegister,
        'retryAfter': retryAfter,
        if (isRegister) 'registerBody': _registerBody(emailText),
      },
    );
  }

  Future<List<String>> loadCountries() async {
    if (_countries.isNotEmpty) return _countries;
    try {
      _countries = await auth.countries();
    } on ApiException catch (e) {
      formError.value = ApiMessages.of(e);
    }
    return _countries;
  }

  Future<List<String>> loadCities() async {
    if (country.text.isEmpty) return [];
    try {
      return await auth.cities(country.text);
    } on ApiException catch (e) {
      formError.value = ApiMessages.of(e);
      return [];
    }
  }

  void setCountry(String value) {
    country.text = value;
    city.clear();
  }

  @override
  void onClose() {
    for (final c in [email, username, mobile, country, city]) {
      c.dispose();
    }
    super.onClose();
  }
}
