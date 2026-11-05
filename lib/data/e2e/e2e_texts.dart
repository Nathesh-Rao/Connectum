/// The words the web shows for end-to-end encryption
/// (`E2E_WEB_COMPLETE.md` section I, `E2E_NEW_DEVICE_AND_HISTORY.md` 3.3 and
/// 7.2), worded for a phone where the web says "browser".
class E2eTexts {
  E2eTexts._();

  // ---- a message this phone cannot open (keyed by the failure code) ----------

  static const unreadable = "🔒 This message can't be read on this device.";

  static const _unreadableByCode = {
    'not_for_this_device':
        "🔒 Sent before this phone was set up for encryption, so it can't be opened here. Approve this device on another device you already use and it will show here, or open it on the device you used then, or enter your recovery code (if you switched recovery on before it was sent).",
    'key_changed':
        "🔒 This sender's security key changed. Check the safety number before trusting new messages.",
    'bad_signature': '🔒 This message could not be verified and was hidden.',
    'no_device':
        '🔒 Encryption is not ready on this device yet. Restart the app or sign in again.',
    'unknown_sender_device':
        "🔒 The sender's device is not known yet. Restart the app to try again.",
    'decrypt_failed': '🔒 This message is damaged and could not be opened.',
    'wrong_conversation':
        '🔒 This message does not belong to this conversation and was hidden.',
    'bad_payload': '🔒 This message could not be read.',
  };

  /// The placeholder for a failure [code]; any other code (or none) gets the
  /// generic line, as on the web.
  static String unreadableFor(String? code) =>
      _unreadableByCode[code] ?? unreadable;

  static Iterable<String> get unreadableCodes => _unreadableByCode.keys;

  // ---- contacts and keys -----------------------------------------------------

  /// Templates: `{user}` is filled with "@name" so it can stand out.
  static const keyChangedTemplate =
      "{user}'s security key changed. Open the lock in the chat header and check the safety number.";

  static String keyChangedNotice(String user) =>
      keyChangedTemplate.replaceFirst('{user}', '@$user');

  static String newDeviceTemplate({required bool hasLabels}) =>
      '{user} added a new device${hasLabels ? ' ({devices})' : ''}. Messages you send them now are encrypted for it too. If that surprises you, check the safety number in the lock at the top of the chat.';

  static String newDeviceNotice(String user, List<String> labels) =>
      newDeviceTemplate(hasLabels: labels.isNotEmpty)
          .replaceFirst('{user}', '@$user')
          .replaceFirst('{devices}', labels.join(', '));

  // ---- approving a new device on this phone ----------------------------------

  /// Templates with `{device}`, for a name that stands out.
  static const approveTitleTemplate = 'Show your earlier messages on {device}?';
  static const continueTitleTemplate =
      'Continue showing your earlier messages on {device}?';
  static const approveRunningTemplate =
      'Showing your earlier messages on {device}';
  static const allSetBodyTemplate =
      'Your earlier messages are now on {device}.';

  static String approveTitle(String device) =>
      approveTitleTemplate.replaceFirst('{device}', device);
  static const approveBody =
      'This device was just added to your account. If it is yours, approve it and your earlier messages will appear there. If you do not recognise it, remove it.';
  static const approve = 'Approve';
  static const notMe = 'That is not me';
  static const later = 'Later';
  static const removeNow = 'Remove it now';
  static String approveRunning(String device) =>
      approveRunningTemplate.replaceFirst('{device}', device);
  static String approveProgress(int n) =>
      '$n messages done. Keep this app open until it finishes.';
  static const allSet = 'All set';
  static String allSetBody(String device) =>
      allSetBodyTemplate.replaceFirst('{device}', device);
  static const couldNotFinish = 'Could not finish';
  static const tryAgain = 'Try again';
  static const stopped = 'Stopped.';

  // ---- waiting for earlier messages (this phone is the new device) ------------

  static const waitingTitle = 'Your earlier messages are not shown here yet';
  static const gotIt = 'Got it';
  static const enterRecoveryCode = 'Enter recovery code';

  // ---- recovery ---------------------------------------------------------------

  static const recoveryOff =
      'Recovery keeps a backup of your messages that only your code can open. If you lose every device, sign in on a new one, enter the code, and your messages come back. Only you have the code: not us, and not the company.';
  static const recoveryTurnOn = 'Turn on recovery and back up';
  static const recoveryCodeShown =
      'Your recovery code. Write it down or keep it somewhere safe. It is shown only now and is not stored anywhere we can read. It is the only way to bring your messages back if you lose every device.';
  static const copy = 'Copy';
  static const savedIt = 'I have saved it';
  static const recoveryBackingUp = 'Backing up your earlier messages';
  static const recoveryRestoring = 'Bringing your earlier messages back';
  static const recoveryBackedUp = 'Your earlier messages are backed up';
  static const recoveryBackedUpBody =
      'If you ever lose every device, sign in on a new one and enter your recovery code.';
  static const recoveryRestored = 'Your earlier messages are back';
  static const recoveryRestoredBody =
      'They open on this device now, without the code.';
  static const recoveryBackupFailed = 'The backup did not finish';
  static const recoveryRestoreFailed = 'Nothing could be brought back';
  static const recoveryOnHere =
      'Recovery is on for your account. To bring your messages back on this device, enter your recovery code.';
  static const recoveryRestoreButton = 'Bring my messages back';
  static const recoveryTurnOffAsk =
      'Turn recovery off? The backup is deleted and your code opens nothing any more.';
  static const recoveryTurnOffYes = 'Yes, turn it off';
  static const recoveryKeep = 'Keep it';
  static const recoveryIsOff =
      'Recovery is off. The backup is deleted and your code opens nothing any more.';
  static const recoverySuggestTitle = 'Back up your messages';
  static const recoverySuggestBody =
      'If you lose your phone, a recovery code brings your messages back on a new one. Only you have the code: not us, and not the company.';
  static const recoverySuggestSetUp = 'Set it up';
  static const recoverySuggestNotNow = 'Not now';

  /// `bad_code` and `wrong_code`.
  static const badCode =
      'A recovery code has 26 letters and numbers, for example ABCDE-FGHJK-LMNPQ-RSTUV-WXYZ2-3.';
  static const wrongCode =
      'That code does not open the recovery key. Check it and try again.';

  // ---- device limit (the web's words: `E2E_NEW_DEVICE_AND_HISTORY.md` 7.1,
  // ---- `E2E_WEB_COMPLETE.md` section I "Devices") ---------------------------

  static const limitTitle = 'Device limit reached';
  static String limitBody(int max) =>
      'This account already has $max devices; remove one first. Each browser or phone you sign in on has its own keys. Remove any you no longer use, and this phone is set up as soon as there is room.';
  static const limitServer =
      'At most {max} devices per person: remove one first.';
  static const rateLimited = 'Too many device registrations; try again later.';
  static const thisPhone = 'This phone';
  static const removeTitle = 'Remove this device?';
  static String removeBody(String when) =>
      '{name} was last used $when. It stops receiving new encrypted messages, and it deletes its keys the next time it starts, so it has to be set up again to read them.';
  static const removeThisBody =
      "{name} is this phone. Its keys are deleted here, and you won't be able to read new encrypted messages on it until you set it up again.";
  static const limitRegistering = 'Setting up this phone';
  static const limitRegisteringBody = 'Adding it to your encryption devices.';
  static const limitDone = 'This phone is set up';
  static const limitDoneBody = 'Secure messaging is set up on this phone.';
  static const limitLoadFailed = "Couldn't read your devices.";
  static const limitBanner =
      'Device limit reached. Remove a device you no longer use to send encrypted messages from this phone.';
  static const limitComposer =
      "Can't send in this encrypted chat until this phone has room.";
  static const limitSeeDevices = 'See devices';
  static const removedTemplate = 'Removed "{label}".';
  static String couldNotStart(String reason) =>
      'Encryption could not start on this device: $reason';

  /// The reason a registration was refused, in the web's words.
  static String registrationFailure(String code, String message, int max) =>
      switch (code) {
        'limit' => limitServer.replaceFirst('{max}', '${max > 0 ? max : 10}'),
        'rate_limited' => rateLimited,
        _ => message.isEmpty ? code : message,
      };

  /// "just now", "5 minutes ago", "yesterday", "3 weeks ago".
  static String ago(int ms, DateTime now) {
    if (ms <= 0) return 'a while ago';
    final span = now.difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (span.inMinutes < 1) return 'just now';
    if (span.inHours < 1) {
      final n = span.inMinutes;
      return n == 1 ? '1 minute ago' : '$n minutes ago';
    }
    if (span.inDays < 1) {
      final n = span.inHours;
      return n == 1 ? '1 hour ago' : '$n hours ago';
    }
    if (span.inDays == 1) return 'yesterday';
    if (span.inDays < 14) return '${span.inDays} days ago';
    if (span.inDays < 60) return '${span.inDays ~/ 7} weeks ago';
    if (span.inDays < 730) return '${span.inDays ~/ 30} months ago';
    return '${span.inDays ~/ 365} years ago';
  }
}
