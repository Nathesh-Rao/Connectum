import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/data/app_countries.dart';
import '../../core/data/country_lookup.dart';
import '../../core/routes/app_routes.dart';
import '../../core/routes/invite_service.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/models/auth_flow.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../invite_code/invite_code_sheet.dart';
import 'auth_validators.dart';

class AuthenticationController extends GetxController
    with GetSingleTickerProviderStateMixin {
  AuthenticationController({
    required this.auth,
    required this.session,
    required this.connectivity,
    required this.invite,
  });

  static const _loginNoticeKey = 'login-notice';
  static const tabLabels = ['Sign in', 'Set up', 'Self register'];

  final AuthRepository auth;
  final SessionRepository session;
  final ConnectivityService connectivity;
  final InviteService invite;

  // One email for all three modes; every other field belongs to one mode and
  // keeps its value while the person switches tabs.
  final email = TextEditingController();
  final orgName = TextEditingController();
  final ownerName = TextEditingController();
  final setupMobile = TextEditingController();
  final username = TextEditingController();
  final regMobile = TextEditingController();
  final country = TextEditingController();
  final state = TextEditingController();
  final city = TextEditingController();

  final focus = <String, FocusNode>{
    for (final key in [
      'email',
      'org',
      'name',
      'setupMobile',
      'username',
      'regMobile',
    ])
      key: FocusNode(),
  };

  late final TabController tabController;

  /// 0 = Sign in, 1 = Set up, 2 = Self register.
  final mode = 0.obs;

  /// +1 when the tab changed towards a higher index, -1 towards a lower one.
  int direction = 1;

  final isBusy = false.obs;
  final isMoreOpen = false.obs;
  final formError = RxnString();
  final serverErrors = <String, String>{}.obs;
  final touched = <String>{}.obs;
  final submitAttempted = false.obs;
  final revision = 0.obs;
  final setupIso = CountryLookup.deviceDefault().iso.obs;
  final regIso = CountryLookup.deviceDefault().iso.obs;

  List<String> _countries = [];

  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  AppCountry countryFor(RxString iso) =>
      CountryLookup.byIso(iso.value) ??
      CountryLookup.byIso(CountryLookup.fallbackIso)!;

  @override
  void onInit() {
    super.onInit();
    invite.attach();
    final prefill = session.loginEmail.value;
    if (prefill != null) {
      email.text = prefill;
      session.loginEmail.value = null;
    }
    tabController = TabController(
      length: tabLabels.length,
      vsync: this,
      animationDuration: AppDurations.base,
    )..addListener(_onTab);
    focus.forEach((key, node) {
      node.addListener(() {
        if (!node.hasFocus) touch(key);
      });
    });
  }

  void _onTab() {
    final index = tabController.index;
    if (index == mode.value) return;
    direction = index > mode.value ? 1 : -1;
    mode.value = index;
    formError.value = null;
    serverErrors.clear();
  }

  @override
  void onReady() {
    super.onReady();
    _showLoginNotice(session.loginNotice.value);
    ever(session.loginNotice, _showLoginNotice);
  }

  void _showLoginNotice(String? text) {
    if (text == null) {
      AppNotices.hide(_loginNoticeKey);
      return;
    }
    AppNotices.show(
      text,
      key: _loginNoticeKey,
      onDismiss: () => session.loginNotice.value = null,
    );
  }

  void openInviteSheet() {
    final context = Get.context;
    if (context != null) InviteCodeSheet.show(context);
  }

  void touch(String key) {
    if (touched.add(key)) revision.value++;
  }

  /// Called on every edit so the inline errors follow the text.
  void changed(String key) {
    serverErrors.remove(key);
    revision.value++;
  }

  void toggleMore() => isMoreOpen.toggle();

  /// The message under a field, only after a submit attempt or after the
  /// person has left the field.
  String? errorFor(String key) {
    revision.value;
    submitAttempted.value;
    touched.length;
    final server = serverErrors[key];
    if (server != null) return server;
    if (!submitAttempted.value && !touched.contains(key)) return null;
    return _check(key);
  }

  String? _check(String key) => switch (key) {
    'email' => AuthValidators.email(email.text),
    'org' => AuthValidators.enterpriseName(orgName.text),
    'name' => AuthValidators.personName(ownerName.text),
    'setupMobile' => AuthValidators.mobile(
      setupMobile.text,
      countryFor(setupIso).dial,
      isRequired: true,
    ).error,
    'username' => AuthValidators.username(username.text),
    'regMobile' => AuthValidators.mobile(
      regMobile.text,
      countryFor(regIso).dial,
      isRequired: false,
    ).error,
    _ => null,
  };

  List<String> get _activeKeys => switch (mode.value) {
    0 => ['email'],
    1 => ['org', 'name', 'email', 'setupMobile'],
    _ => ['username', 'email', if (isMoreOpen.value) 'regMobile'],
  };

  void setIso(bool isSetup, AppCountry picked) {
    (isSetup ? setupIso : regIso).value = picked.iso;
    revision.value++;
  }

  void setCountry(String name) {
    country.text = name;
    city.clear();
    final match = CountryLookup.matchName(name);
    if (match != null && regMobile.text.trim().isEmpty) {
      regIso.value = match.iso;
    }
  }

  Future<void> submit() async {
    if (isBusy.value) return;
    submitAttempted.value = true;
    formError.value = null;
    serverErrors.clear();
    for (final key in _activeKeys) {
      if (_check(key) != null) {
        focus[key]?.requestFocus();
        return;
      }
    }
    isBusy.value = true;
    try {
      switch (mode.value) {
        case 0:
          await _signIn();
        case 1:
          await _setUp();
        default:
          await _register();
      }
    } on UnsupportedStep catch (e) {
      formError.value =
          "This account needs a step the mobile app doesn't support yet (${e.reasons.join(', ')}).";
    } on ApiException catch (e) {
      _showServerError(e);
    } finally {
      isBusy.value = false;
    }
  }

  void _showServerError(ApiException e) {
    final fields = e.fieldErrors;
    if (fields.isNotEmpty) {
      serverErrors.assignAll(fields);
    } else if (e.code == 'invalid_mobile') {
      serverErrors[mode.value == 1 ? 'setupMobile' : 'regMobile'] =
          AuthValidators.mobileError;
    } else if (e.code == 'no_account' && mode.value == 0 && invite.hasInvite) {
      // An invited person with a new email goes on to create the account.
      tabController.animateTo(2);
      formError.value =
          'No account for that email yet. Create one to join ${invite.organisationName ?? 'this enterprise'}.';
    } else if (e.code == 'exists' || e.code == 'no_account') {
      serverErrors['email'] = ApiMessages.of(e);
    } else {
      formError.value = ApiMessages.of(e);
    }
  }

  Future<void> _signIn() async {
    final result = await auth.startLogin(email.text.trim());
    switch (result.kind) {
      case LoginStartKind.trusted:
        Get.offAllNamed(AppRoutes.enterprises);
      case LoginStartKind.throttled:
        _openVerification(AuthFlow.login, null, result.retryAfter);
      case LoginStartKind.codeSent:
        _openVerification(AuthFlow.login, null, 30);
    }
  }

  Map<String, dynamic> _setupBody() => {
    'org': orgName.text.trim(),
    'name': ownerName.text.trim(),
    'email': email.text.trim(),
    'mobile': AuthValidators.mobile(
      setupMobile.text,
      countryFor(setupIso).dial,
      isRequired: true,
    ).value,
  };

  Future<void> _setUp() async {
    final body = _setupBody();
    _logRequest('setup', body);
    final result = await auth.startSetup(body);
    _openVerification(
      AuthFlow.setup,
      body,
      result.kind == LoginStartKind.throttled ? result.retryAfter : 30,
    );
  }

  Map<String, dynamic> _registerBody() {
    final mobile = AuthValidators.mobile(
      regMobile.text,
      countryFor(regIso).dial,
      isRequired: false,
    ).value;
    return {
      'username': AuthValidators.normaliseUsername(username.text),
      'email': email.text.trim(),
      if (mobile.isNotEmpty) 'mobile': mobile,
      if (country.text.trim().isNotEmpty) 'country': country.text.trim(),
      if (state.text.trim().isNotEmpty) 'state': state.text.trim(),
      if (city.text.trim().isNotEmpty) 'city': city.text.trim(),
    };
  }

  Future<void> _register() async {
    final body = _registerBody();
    _logRequest('register', body);
    await auth.startRegister(body);
    _openVerification(AuthFlow.register, body, 30);
  }

  // Debug only: shows which request was built, without the values.
  void _logRequest(String name, Map<String, dynamic> body) {
    if (kDebugMode) {
      debugPrint('auth: $name/start body keys ${body.keys.toList()}');
    }
  }

  void _openVerification(
    AuthFlow flow,
    Map<String, dynamic>? body,
    int retryAfter,
  ) {
    Get.toNamed(
      AppRoutes.verification,
      arguments: {
        'email': email.text.trim(),
        'flow': flow.name,
        'retryAfter': retryAfter,
        'body': ?body,
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

  @override
  void onClose() {
    AppNotices.hide(_loginNoticeKey);
    invite.detach();
    tabController.dispose();
    for (final c in [
      email,
      orgName,
      ownerName,
      setupMobile,
      username,
      regMobile,
      country,
      state,
      city,
    ]) {
      c.dispose();
    }
    for (final f in focus.values) {
      f.dispose();
    }
    super.onClose();
  }
}
