import 'package:webcrypto/webcrypto.dart';

class E2eException implements Exception {
  const E2eException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'E2eException($code)';
}

/// A device's public record as the server lists it.
class E2eDevicePublic {
  const E2eDevicePublic({
    required this.id,
    required this.ecdh,
    required this.sign,
    this.label = '',
    this.ts = 0,
    this.seen = 0,
    this.isRecovery = false,
    this.isLate = false,
  });

  final String id;
  final String ecdh;
  final String sign;
  final String label;
  final int ts;

  /// When the server last saw this device (`seen`, recorded at most hourly),
  /// 0 when not reported.
  final int seen;

  /// The recovery key, listed by the server as a device (`recovery: true`). It
  /// is wrapped for like any device but is not one of a person's devices.
  final bool isRecovery;

  /// `late` from the server: added after another device existed, so earlier
  /// messages have no box for it until an older device hands them on.
  final bool isLate;
}

enum E2eReadState { ok, cantDecrypt, pending }

/// The outcome of opening one envelope. [code] is the failure code from the
/// handoff doc, for the log only.
class E2eReading {
  const E2eReading.ok(String this.text) : state = E2eReadState.ok, code = null;

  const E2eReading.cannot(String this.code)
    : state = E2eReadState.cantDecrypt,
      text = null;

  const E2eReading.pending()
    : state = E2eReadState.pending,
      text = null,
      code = null;

  final E2eReadState state;
  final String? text;
  final String? code;
}

/// This device's two key pairs. The public halves are base64url of the raw
/// 65-byte point.
class E2eDeviceKeys {
  const E2eDeviceKeys({
    required this.id,
    required this.ecdhPrivate,
    required this.signPrivate,
    required this.ecdhPub,
    required this.signPub,
  });

  final String id;
  final EcdhPrivateKey ecdhPrivate;
  final EcdsaPrivateKey signPrivate;
  final String ecdhPub;
  final String signPub;

  E2eDevicePublic get asPublic =>
      E2eDevicePublic(id: id, ecdh: ecdhPub, sign: signPub);
}

class E2eEnvelope {
  const E2eEnvelope({
    required this.mid,
    required this.from,
    required this.dev,
    required this.conv,
    required this.ts,
    required this.ek,
    required this.iv,
    required this.ct,
    required this.sig,
    required this.keys,
  });

  final String mid;
  final String from;
  final String dev;
  final String conv;
  final int ts;
  final String ek;
  final String iv;
  final String ct;
  final String sig;

  /// Recipient device id -> `{iv, w}`, plus `ek` when the box was made later
  /// and carries its own one-time key.
  final Map<String, Map<String, String>> keys;
}

class E2eOpened {
  const E2eOpened({
    required this.text,
    required this.from,
    required this.dev,
    required this.mid,
    required this.ts,
    required this.conv,
  });

  final String text;
  final String from;
  final String dev;
  final String mid;
  final int ts;
  final String conv;
}

class E2eEncryptedFile {
  const E2eEncryptedFile({
    required this.ciphertext,
    required this.key,
    required this.iv,
  });

  final List<int> ciphertext;
  final String key;
  final String iv;
}

enum E2eSendVerdict { plain, encrypt, blocked, unknown }

/// What a send into a direct message must do. [plain] is the only verdict
/// that lets text leave the phone unencrypted.
class E2eSendDecision {
  const E2eSendDecision.plain()
    : verdict = E2eSendVerdict.plain,
      headline = null,
      reason = null,
      recipients = const [],
      keys = null,
      isKeyChange = false,
      isTransient = false,
      isSetupPending = false,
      keyChangeUser = null;

  const E2eSendDecision.unknown()
    : verdict = E2eSendVerdict.unknown,
      headline = null,
      reason = null,
      recipients = const [],
      keys = null,
      isKeyChange = false,
      isTransient = false,
      isSetupPending = false,
      keyChangeUser = null;

  const E2eSendDecision.encrypt({
    required this.recipients,
    required E2eDeviceKeys this.keys,
  }) : verdict = E2eSendVerdict.encrypt,
       headline = null,
       reason = null,
       isKeyChange = false,
       isTransient = false,
       isSetupPending = false,
       keyChangeUser = null;

  /// [isTransient]: may work on a later try (a lookup failed), so the composer
  /// stays open and the message fails at send time with a retry.
  const E2eSendDecision.blocked(
    String this.headline, {
    this.reason,
    this.isKeyChange = false,
    this.isTransient = false,
    this.keyChangeUser,
  }) : verdict = E2eSendVerdict.blocked,
       isSetupPending = false,
       recipients = const [],
       keys = null;

  /// This phone has no keys yet and setup is running: blocked in the composer,
  /// but a message already queued waits instead of failing.
  const E2eSendDecision.setupPending()
    : verdict = E2eSendVerdict.blocked,
      headline = settingUp,
      reason = null,
      recipients = const [],
      keys = null,
      isKeyChange = false,
      isTransient = false,
      isSetupPending = true,
      keyChangeUser = null;

  /// Stored in `fail_reason` of a message that could not be sent securely;
  /// [Message.secureFailure] strips it again.
  static const failTag = 'e2e:';
  static const cantSend = "Can't send securely right now";

  /// No tag: the bubble then reads "Not sent. Tap to retry".
  static const staleFailure = 'stale devices';
  static const settingUp = 'Setting up secure messaging';
  static const notSetUpReason = "secure messaging isn't set up on this phone";

  final E2eSendVerdict verdict;
  final String? headline;
  final String? reason;
  final List<E2eDevicePublic> recipients;
  final E2eDeviceKeys? keys;
  final bool isKeyChange;
  final bool isTransient;
  final bool isSetupPending;
  final String? keyChangeUser;

  bool get isBlocked => verdict == E2eSendVerdict.blocked;
  bool get isEncrypt => verdict == E2eSendVerdict.encrypt;

  /// The sentence shown to the person.
  String get message => reason == null ? '$headline' : '$headline: $reason';
}

/// A device whose key differs from the one pinned when it was first seen.
class E2ePinChange {
  const E2ePinChange({required this.user, required this.device});

  final String user;
  final E2eDevicePublic device;
}

/// What the key-changed sheet shows.
class E2eKeyReview {
  const E2eKeyReview({
    required this.user,
    required this.safetyNumber,
    required this.devices,
    required this.changed,
  });

  final String user;
  final String safetyNumber;

  /// The directory as the sheet saw it; trusting pins exactly these.
  final Map<String, List<E2eDevicePublic>> devices;
  final List<E2ePinChange> changed;
}

/// Something to tell the person that the web tells with a toast.
class E2eNotice {
  const E2eNotice.keyChanged(this.user)
    : labels = const [],
      isNewDevice = false;

  const E2eNotice.newDevice(this.user, this.labels) : isNewDevice = true;

  final String user;
  final List<String> labels;
  final bool isNewDevice;
}
