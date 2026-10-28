import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/repositories/auth_repository.dart';

class VerificationController extends GetxController {
  VerificationController({
    required this.auth,
    required this.email,
    required this.isRegister,
    required this.registerBody,
    required int retryAfter,
  }) : _initialResend = retryAfter;

  static const length = 6;
  static const maxTries = 5;
  static const resendSeconds = 30;
  // An empty cell holds this invisible character so that backspace on an
  // empty cell still produces a text change (soft keyboards send no key event).
  static const _blank = '​';

  final AuthRepository auth;
  final String email;
  final bool isRegister;
  final Map<String, dynamic>? registerBody;
  final int _initialResend;

  final cells = List.generate(
    length,
    (_) => TextEditingController(text: _blank),
  );
  final focusNodes = List.generate(length, (_) => FocusNode());

  final _filled = List.filled(length, false);

  final isBusy = false.obs;
  final message = RxnString();
  final triesLeft = maxTries.obs;
  final resendIn = 0.obs;
  final shakeTick = 0.obs;
  final blockedReasons = <String>[].obs;

  Timer? _timer;

  bool get isLocked => triesLeft.value <= 0;

  @override
  void onInit() {
    super.onInit();
    _startResendTimer(_initialResend);
  }

  @override
  void onReady() {
    super.onReady();
    focusNodes.first.requestFocus();
  }

  void _startResendTimer(int seconds) {
    _timer?.cancel();
    resendIn.value = seconds;
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      resendIn.value -= 1;
      if (resendIn.value <= 0) t.cancel();
    });
  }

  String get code =>
      cells.map((c) => c.text.replaceAll(RegExp(r'\D'), '')).join();

  void _set(int i, String digit) {
    _filled[i] = digit.isNotEmpty;
    final text = digit.isEmpty ? _blank : digit;
    cells[i].value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void onCellChanged(int i, String raw) {
    message.value = null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      // Backspace: clear this cell, or step back from an empty one.
      final wasEmpty = !_filled[i];
      _set(i, '');
      if (raw.isEmpty && i > 0 && wasEmpty) {
        _set(i - 1, '');
        focusNodes[i - 1].requestFocus();
      }
      return;
    }
    if (digits.length == 1) {
      _set(i, digits);
    } else if (digits.length == 2 && _filled[i]) {
      // Typed into a filled cell (focus had not moved on yet): the new digit
      // belongs to the next cell.
      if (i + 1 < length) {
        _set(i, digits[0]);
        _set(i + 1, digits[1]);
      } else {
        _set(i, digits[1]);
      }
      focusNodes[(i + 2).clamp(0, length - 1)].requestFocus();
      if (code.length == length) submit();
      return;
    } else {
      // Paste: spread the digits from this cell onwards.
      for (var k = 0; k < digits.length && i + k < length; k++) {
        _set(i + k, digits[k]);
      }
    }
    final next = digits.length > 2
        ? (i + digits.length).clamp(0, length - 1)
        : i + 1;
    if (code.length == length) {
      focusNodes[length - 1].unfocus();
      submit();
    } else if (next < length) {
      focusNodes[next].requestFocus();
    }
  }

  void _clearCells() {
    for (var i = 0; i < length; i++) {
      _set(i, '');
    }
    focusNodes.first.requestFocus();
  }

  Future<void> submit() async {
    if (isBusy.value || isLocked || code.length != length) return;
    isBusy.value = true;
    try {
      if (isRegister) {
        await auth.verifyRegister(email, code);
      } else {
        await auth.verifyLogin(email, code);
      }
      Get.offAllNamed(AppRoutes.enterprises);
    } on UnsupportedStep catch (e) {
      blockedReasons.assignAll(e.reasons);
    } on ApiException catch (e) {
      _onError(e);
    } finally {
      isBusy.value = false;
    }
  }

  void _onError(ApiException e) {
    if (e.code == 'otp_locked') {
      triesLeft.value = 0;
      message.value = ApiMessages.of(e);
    } else if (e.code == 'otp_invalid' &&
        !e.message.toLowerCase().contains('expire')) {
      triesLeft.value -= 1;
      message.value = triesLeft.value > 0
          ? "That code isn't right. ${triesLeft.value} ${triesLeft.value == 1 ? 'try' : 'tries'} left."
          : 'Too many wrong codes. Ask for a new code.';
    } else {
      message.value = ApiMessages.of(e);
    }
    shakeTick.value += 1;
    _clearCells();
  }

  Future<void> resend() async {
    if (resendIn.value > 0 || isBusy.value) return;
    isBusy.value = true;
    try {
      if (isRegister) {
        await auth.startRegister(registerBody!);
        _startResendTimer(resendSeconds);
      } else {
        final result = await auth.startLogin(email);
        if (result.kind == LoginStartKind.trusted) {
          Get.offAllNamed(AppRoutes.enterprises);
          return;
        }
        _startResendTimer(
          result.kind == LoginStartKind.throttled
              ? result.retryAfter
              : resendSeconds,
        );
      }
      triesLeft.value = maxTries;
      message.value = 'A new code is on its way.';
      _clearCells();
    } on ApiException catch (e) {
      message.value = ApiMessages.of(e);
    } finally {
      isBusy.value = false;
    }
  }

  void changeEmail() => Get.back<void>();

  @override
  void onClose() {
    _timer?.cancel();
    for (final c in cells) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
    super.onClose();
  }
}
