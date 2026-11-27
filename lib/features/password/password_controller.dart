import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/session_store.dart';

/// Set, change or remove the account's own password (the web's "Set a
/// password" panel): a code emailed to the account confirms it, then the
/// new password. No current password is asked. This device stays signed in;
/// the server ends the account's other sessions.
class PasswordController extends GetxController {
  PasswordController({required this.auth, required this.store});

  static const minLength = 8;
  static const maxLength = 128;

  final AuthRepository auth;
  final SessionStore store;

  final code = TextEditingController();
  final newPassword = TextEditingController();

  /// False: "send me a code". True: the code and the new password.
  final isCodeSent = false.obs;
  final isBusy = false.obs;
  final isHidden = true.obs;
  final error = RxnString();
  final info = RxnString();
  final revision = 0.obs;

  /// The server's own words about the typed password (`password/check`),
  /// null while it is fine or unknown.
  final hint = RxnString();
  Timer? _checkTimer;
  int _checkSeq = 0;

  bool get hasPassword => store.identity.value?.hasPassword ?? false;

  bool get canSave {
    revision.value;
    return code.text.length == 6 && newPassword.text.runes.length >= minLength;
  }

  bool get canRemove {
    revision.value;
    return code.text.length == 6;
  }

  void changed() {
    error.value = null;
    revision.value++;
  }

  /// A debounced `password/check` of the new password. The password is sent
  /// as typed and never kept; a failed check shows nothing.
  void passwordChanged() {
    changed();
    _checkTimer?.cancel();
    hint.value = null;
    final text = newPassword.text;
    if (text.isEmpty) return;
    final seq = ++_checkSeq;
    _checkTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final result = await auth.passwordCheck(text);
        if (seq == _checkSeq && !isClosed) {
          hint.value = result.isOk ? null : result.message;
        }
      } catch (e, st) {
        AppLog.e('password_controller', e, st);
        // The save still asks the server again.
      }
    });
  }

  void toggleHidden() => isHidden.toggle();

  Future<void> sendCode() async {
    if (isBusy.value) return;
    await _run(() async {
      final result = await auth.startPasswordChange();
      isCodeSent.value = true;
      info.value = result.kind == LoginStartKind.throttled
          ? 'A code was just sent. You can ask for another in ${result.retryAfter} seconds.'
          : 'We sent a 6-digit code to ${store.identity.value?.email ?? 'your email'}.';
    });
  }

  Future<void> save() async {
    if (isBusy.value) return;
    final text = newPassword.text;
    final length = text.runes.length;
    if (length < minLength) {
      error.value = 'Choose a password of at least $minLength characters.';
      return;
    }
    if (length > maxLength) {
      error.value =
          'That password is too long ($maxLength characters at most).';
      return;
    }
    await _run(() async {
      await auth.setPassword(code.text.trim(), text);
      _done(
        'Your password is set. You can sign in with it, or with an emailed code.',
      );
    });
  }

  Future<void> remove() async {
    if (isBusy.value || code.text.length != 6) return;
    await _run(() async {
      await auth.removePassword(code.text.trim());
      _done('Your password is removed. Sign in with an emailed code.');
    });
  }

  void _done(String message) {
    code.clear();
    newPassword.clear();
    TextInput.finishAutofillContext();
    AppNotices.show(message, variant: AppNoticeVariant.success);
    Get.back<void>();
  }

  Future<void> _run(Future<void> Function() body) async {
    error.value = null;
    isBusy.value = true;
    try {
      await body();
    } on ApiException catch (e) {
      error.value = ApiMessages.ofPasswordChange(e);
    } catch (e, st) {
      AppLog.e('password_controller', e, st);
      debugPrint('password request failed: ${e.runtimeType}');
      if (!isClosed) error.value = "Something went wrong. Try again.";
    } finally {
      if (!isClosed) isBusy.value = false;
    }
  }

  @override
  void onClose() {
    _checkTimer?.cancel();
    code.dispose();
    newPassword.dispose();
    super.onClose();
  }
}
