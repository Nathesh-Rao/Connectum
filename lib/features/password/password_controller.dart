import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_messages.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/session_store.dart';

/// Set, change or remove the account's own password (the web's "Set a
/// password" panel): a code emailed to the account confirms it, then the
/// new password. No current password is asked and other sessions stay.
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

  bool get hasPassword => store.identity.value?.hasPassword ?? false;

  bool get canSave {
    revision.value;
    return code.text.length == 6 && newPassword.text.length >= minLength;
  }

  bool get canRemove {
    revision.value;
    return code.text.length == 6;
  }

  void changed() {
    error.value = null;
    revision.value++;
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
    if (text.length < minLength) {
      error.value = 'Choose a password of at least $minLength characters.';
      return;
    }
    if (text.length > maxLength) {
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
      error.value = ApiMessages.of(e);
    } catch (e) {
      debugPrint('password request failed: ${e.runtimeType}');
      if (!isClosed) error.value = "Something went wrong. Try again.";
    } finally {
      if (!isClosed) isBusy.value = false;
    }
  }

  @override
  void onClose() {
    code.dispose();
    newPassword.dispose();
    super.onClose();
  }
}
