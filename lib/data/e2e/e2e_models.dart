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
  });

  final String id;
  final String ecdh;
  final String sign;
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

  /// Recipient device id -> `{iv, w}`.
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
