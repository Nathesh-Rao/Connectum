import 'dart:convert';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

import 'e2e_models.dart';
import 'e2e_random.dart';

/// The end-to-end primitives, byte for byte as `mobile-handoff/e2e.md`
/// describes them: no networking, no storage.
class E2eCrypto {
  E2eCrypto({E2eRandom? random}) : _random = random ?? E2eRandom();

  static const prefix = 'e2e1:';
  static const version = 1;
  static const _pad = 64;
  static final _b64uPattern = RegExp(r'^[A-Za-z0-9_-]*$');

  final E2eRandom _random;

  // ---- encodings --------------------------------------------------------

  static String encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Strict: no padding, no characters outside the url-safe alphabet.
  static Uint8List decode(String text) {
    if (!_b64uPattern.hasMatch(text) || text.length % 4 == 1) {
      throw const E2eException('bad_encoding', 'not valid base64url');
    }
    final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
    return Uint8List.fromList(base64Url.decode(padded));
  }

  static Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

  static bool isEnvelope(String? text) =>
      text != null && text.startsWith(prefix);

  /// The `mid` inside an envelope, or null when [text] is not one.
  static String? midOf(String? text) {
    if (!isEnvelope(text)) return null;
    try {
      final json = jsonDecode(text!.substring(prefix.length));
      final mid = json is Map ? json['mid'] : null;
      return mid is String && mid.isNotEmpty ? mid : null;
    } catch (_) {
      return null;
    }
  }

  /// `dm:` plus both lower-cased names sorted, or `group:` plus the name.
  static String dmLabel(String a, String b) {
    final names = [a, b].map((n) => n.toLowerCase()).toList()..sort();
    return 'dm:${names.join('|')}';
  }

  static String groupLabel(String name) => 'group:${name.trim().toLowerCase()}';

  String newDeviceId() =>
      _random.bytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String newMessageId() => encode(_random.bytes(16));

  // ---- device keys ------------------------------------------------------

  Future<E2eDeviceKeys> generateDeviceKeys() async {
    final ecdh = await EcdhPrivateKey.generateKey(EllipticCurve.p256);
    final sign = await EcdsaPrivateKey.generateKey(EllipticCurve.p256);
    return E2eDeviceKeys(
      id: newDeviceId(),
      ecdhPrivate: ecdh.privateKey,
      signPrivate: sign.privateKey,
      ecdhPub: encode(await ecdh.publicKey.exportRawKey()),
      signPub: encode(await sign.publicKey.exportRawKey()),
    );
  }

  /// Rebuilds keys from private scalars and their public points. Used by the
  /// self-test with the vectors' fixed test keys.
  Future<E2eDeviceKeys> importDeviceKeys({
    required String id,
    required Uint8List ecdhScalar,
    required Uint8List signScalar,
    required String ecdhPub,
    required String signPub,
  }) async {
    return E2eDeviceKeys(
      id: id,
      ecdhPrivate: await EcdhPrivateKey.importJsonWebKey(
        _jwk(ecdhScalar, decode(ecdhPub)),
        EllipticCurve.p256,
      ),
      signPrivate: await EcdsaPrivateKey.importJsonWebKey(
        _jwk(signScalar, decode(signPub)),
        EllipticCurve.p256,
      ),
      ecdhPub: ecdhPub,
      signPub: signPub,
    );
  }

  Map<String, dynamic> _jwk(Uint8List scalar, Uint8List point) => {
    'kty': 'EC',
    'crv': 'P-256',
    'd': encode(scalar),
    'x': encode(point.sublist(1, 33)),
    'y': encode(point.sublist(33, 65)),
  };

  Future<EcdhPublicKey> _importEcdhPublic(String b64) {
    final raw = decode(b64);
    if (raw.length != 65 || raw[0] != 4) {
      throw const E2eException('bad_key', 'not an uncompressed P-256 point');
    }
    return EcdhPublicKey.importRawKey(raw, EllipticCurve.p256);
  }

  Future<EcdsaPublicKey> _importSignPublic(String b64) {
    final raw = decode(b64);
    if (raw.length != 65 || raw[0] != 4) {
      throw const E2eException('bad_key', 'not an uncompressed P-256 point');
    }
    return EcdsaPublicKey.importRawKey(raw, EllipticCurve.p256);
  }

  // ---- registration proof ----------------------------------------------

  static String registrationMessage({
    required String user,
    required String id,
    required String ecdhPub,
    required String signPub,
  }) => 'connectum-e2e-register|$user|$id|$ecdhPub|$signPub';

  Future<String> registrationProof({
    required String user,
    required E2eDeviceKeys keys,
  }) async {
    final message = registrationMessage(
      user: user,
      id: keys.id,
      ecdhPub: keys.ecdhPub,
      signPub: keys.signPub,
    );
    return encode(
      await keys.signPrivate.signBytes(_utf8(message), Hash.sha256),
    );
  }

  /// False for any bad signature, including one that is not 64 bytes.
  Future<bool> verify({
    required String signPub,
    required String signature,
    required List<int> data,
  }) async {
    final key = await _importSignPublic(signPub);
    try {
      return await key.verifyBytes(decode(signature), data, Hash.sha256);
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyRegistrationProof({
    required String user,
    required String id,
    required String ecdhPub,
    required String signPub,
    required String proof,
  }) => verify(
    signPub: signPub,
    signature: proof,
    data: _utf8(
      registrationMessage(
        user: user,
        id: id,
        ecdhPub: ecdhPub,
        signPub: signPub,
      ),
    ),
  );

  // ---- framing and bound strings ---------------------------------------

  Uint8List _frame(Uint8List bytes) {
    final total = (4 + bytes.length + _pad - 1) ~/ _pad * _pad;
    final out = Uint8List(total);
    ByteData.view(out.buffer).setUint32(0, bytes.length);
    out.setRange(4, 4 + bytes.length, bytes);
    return out;
  }

  Uint8List _unframe(Uint8List bytes) {
    if (bytes.length < 4 || bytes.length % _pad != 0) {
      throw const E2eException('bad_frame', 'bad padding');
    }
    final length = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.length,
    ).getUint32(0);
    if (length > bytes.length - 4) {
      throw const E2eException('bad_frame', 'bad length');
    }
    return Uint8List.sublistView(bytes, 4, 4 + length);
  }

  static Uint8List _msgAad(String mid, String conv, String from, String dev) =>
      _utf8('e2e1-msg|$mid|$conv|$from|$dev');

  static Uint8List _wrapAad(String mid, String recipientDev) =>
      _utf8('e2e1-wrap|$mid|$recipientDev');

  static final _fileAad = _utf8('e2e1-file');

  static String signatureInput({
    required String mid,
    required String from,
    required String dev,
    required String conv,
    required int ts,
    required String ek,
    required String iv,
    required String ct,
  }) => 'e2e1|$mid|$from|$dev|$conv|$ts|$ek|$iv|$ct';

  Future<AesGcmSecretKey> _wrapKey(
    Uint8List shared,
    String mid,
    String recipientDev,
    String senderDev,
  ) async {
    final hkdf = await HkdfSecretKey.importRawKey(shared);
    final bits = await hkdf.deriveBits(
      256,
      Hash.sha256,
      decode(mid),
      _utf8('connectum-e2e-wrap|$recipientDev|$senderDev'),
    );
    return AesGcmSecretKey.importRawKey(bits);
  }

  // ---- building ---------------------------------------------------------

  /// Encrypts [text] for [recipients] (every device that must read it, the
  /// sender's own devices included). Returns the text to send: `e2e1:{...}`.
  Future<String> buildEnvelope({
    required String user,
    required E2eDeviceKeys keys,
    required String conv,
    required List<E2eDevicePublic> recipients,
    required String text,
    int? ts,
  }) async {
    if (recipients.isEmpty) {
      throw const E2eException('no_recipients', 'nobody to encrypt for');
    }
    final mid = newMessageId();
    final from = user.toLowerCase();
    final messageKey = _random.bytes(32);
    final iv = _random.bytes(12);
    final plain = _frame(_utf8(jsonEncode({'v': 1, 't': text})));
    final ct = await (await AesGcmSecretKey.importRawKey(messageKey))
        .encryptBytes(
          plain,
          iv,
          additionalData: _msgAad(mid, conv, from, keys.id),
        );

    final fixed = _random.takeEphemeral();
    final ephemeralPrivate = fixed == null
        ? null
        : await EcdhPrivateKey.importJsonWebKey(
            _jwk(fixed.scalar, fixed.publicPoint),
            EllipticCurve.p256,
          );
    final generated = fixed == null
        ? await EcdhPrivateKey.generateKey(EllipticCurve.p256)
        : null;
    final ephemeral = ephemeralPrivate ?? generated!.privateKey;
    final ek = encode(
      fixed?.publicPoint ?? await generated!.publicKey.exportRawKey(),
    );

    final wraps = <String, Map<String, String>>{};
    for (final r in recipients) {
      final shared = await ephemeral.deriveBits(
        256,
        await _importEcdhPublic(r.ecdh),
      );
      final wrapKey = await _wrapKey(shared, mid, r.id, keys.id);
      final wrapIv = _random.bytes(12);
      final w = await wrapKey.encryptBytes(
        messageKey,
        wrapIv,
        additionalData: _wrapAad(mid, r.id),
      );
      wraps[r.id] = {'iv': encode(wrapIv), 'w': encode(w)};
    }

    final stamp = ts ?? DateTime.now().millisecondsSinceEpoch;
    final ctText = encode(ct);
    final ivText = encode(iv);
    final sig = encode(
      await keys.signPrivate.signBytes(
        _utf8(
          signatureInput(
            mid: mid,
            from: from,
            dev: keys.id,
            conv: conv,
            ts: stamp,
            ek: ek,
            iv: ivText,
            ct: ctText,
          ),
        ),
        Hash.sha256,
      ),
    );
    return prefix +
        jsonEncode({
          'v': version,
          'mid': mid,
          'from': from,
          'dev': keys.id,
          'conv': conv,
          'ts': stamp,
          'ek': ek,
          'iv': ivText,
          'ct': ctText,
          'sig': sig,
          'keys': wraps,
        });
  }

  // ---- opening ----------------------------------------------------------

  E2eEnvelope parseEnvelope(String text) {
    if (!isEnvelope(text)) {
      throw const E2eException('not_envelope', 'not an encrypted message');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(prefix.length));
    } catch (_) {
      throw const E2eException('bad_envelope', 'unreadable envelope');
    }
    const bad = E2eException(
      'bad_envelope',
      'unsupported or malformed envelope',
    );
    if (decoded is! Map<String, dynamic> || decoded['v'] != version) throw bad;
    final json = decoded;
    String str(String key) {
      final value = json[key];
      if (value is! String) throw bad;
      return value;
    }

    final ts = json['ts'];
    final keys = json['keys'];
    if (ts is! num || ts != ts.truncate() || keys is! Map) throw bad;
    final wraps = <String, Map<String, String>>{};
    keys.forEach((id, wrap) {
      if (id is! String || wrap is! Map) return;
      final iv = wrap['iv'];
      final w = wrap['w'];
      if (iv is String && w is String) wraps[id] = {'iv': iv, 'w': w};
    });
    return E2eEnvelope(
      mid: str('mid'),
      from: str('from'),
      dev: str('dev'),
      conv: str('conv'),
      ts: ts.toInt(),
      ek: str('ek'),
      iv: str('iv'),
      ct: str('ct'),
      sig: str('sig'),
      keys: wraps,
    );
  }

  /// Opens an envelope on this device. [signKeyFor] returns the sender
  /// device's signing public key (base64url) or null when it is unknown.
  /// [expectConv] is the conversation the message arrived in.
  Future<E2eOpened> openEnvelope({
    required String text,
    required E2eDeviceKeys keys,
    required Future<String?> Function(String user, String deviceId) signKeyFor,
    String? expectConv,
  }) async {
    final e = parseEnvelope(text);
    if (expectConv != null && e.conv != expectConv) {
      throw const E2eException(
        'wrong_conversation',
        'the message belongs to another conversation',
      );
    }
    final mine = e.keys[keys.id];
    if (mine == null) {
      throw const E2eException(
        'not_for_this_device',
        'this device was not among the recipients',
      );
    }
    final signPub = await signKeyFor(e.from, e.dev);
    if (signPub == null) {
      throw const E2eException(
        'unknown_sender_device',
        'the sender device is not known',
      );
    }
    final isValid = await verify(
      signPub: signPub,
      signature: e.sig,
      data: _utf8(
        signatureInput(
          mid: e.mid,
          from: e.from,
          dev: e.dev,
          conv: e.conv,
          ts: e.ts,
          ek: e.ek,
          iv: e.iv,
          ct: e.ct,
        ),
      ),
    );
    if (!isValid) {
      throw const E2eException(
        'bad_signature',
        'the signature does not match the sender',
      );
    }
    final String payloadText;
    try {
      final shared = await keys.ecdhPrivate.deriveBits(
        256,
        await _importEcdhPublic(e.ek),
      );
      final wrapKey = await _wrapKey(shared, e.mid, keys.id, e.dev);
      final raw = await wrapKey.decryptBytes(
        decode(mine['w']!),
        decode(mine['iv']!),
        additionalData: _wrapAad(e.mid, keys.id),
      );
      final plain = await (await AesGcmSecretKey.importRawKey(raw))
          .decryptBytes(
            decode(e.ct),
            decode(e.iv),
            additionalData: _msgAad(e.mid, e.conv, e.from, e.dev),
          );
      final payload = jsonDecode(utf8.decode(_unframe(plain)));
      final t = payload is Map ? payload['t'] : null;
      if (t is! String) {
        throw const E2eException('bad_payload', 'unexpected payload');
      }
      payloadText = t;
    } on E2eException {
      rethrow;
    } catch (_) {
      throw const E2eException(
        'decrypt_failed',
        'the message could not be decrypted',
      );
    }
    return E2eOpened(
      text: payloadText,
      from: e.from,
      dev: e.dev,
      mid: e.mid,
      ts: e.ts,
      conv: e.conv,
    );
  }

  // ---- attachments ------------------------------------------------------

  Future<E2eEncryptedFile> encryptFile(List<int> bytes) async {
    final key = _random.bytes(32);
    final iv = _random.bytes(12);
    final ct = await (await AesGcmSecretKey.importRawKey(
      key,
    )).encryptBytes(bytes, iv, additionalData: _fileAad);
    return E2eEncryptedFile(ciphertext: ct, key: encode(key), iv: encode(iv));
  }

  Future<Uint8List> decryptFile(
    List<int> ciphertext,
    String key,
    String iv,
  ) async {
    try {
      final secret = await AesGcmSecretKey.importRawKey(decode(key));
      return await secret.decryptBytes(
        ciphertext,
        decode(iv),
        additionalData: _fileAad,
      );
    } catch (_) {
      throw const E2eException(
        'file_decrypt_failed',
        'the attachment could not be decrypted (damaged or wrong key)',
      );
    }
  }

  // ---- safety number and fingerprint -----------------------------------

  Future<String> safetyNumber(
    List<E2eDevicePublic> devicesA,
    List<E2eDevicePublic> devicesB,
  ) async {
    String part(List<E2eDevicePublic> list) {
      final sorted = [...list]..sort((x, y) => x.id.compareTo(y.id));
      return sorted.map((d) => '${d.id}:${d.ecdh}:${d.sign}').join(',');
    }

    final parts = [part(devicesA), part(devicesB)]..sort();
    final digest = await Hash.sha256.digestBytes(
      _utf8('connectum-safety|${parts[0]}|${parts[1]}'),
    );
    final groups = <String>[];
    for (var i = 0; i < 24; i += 2) {
      final n = ((digest[i] << 8) | digest[i + 1]) % 100000;
      groups.add(n.toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  Future<String> deviceFingerprint(E2eDevicePublic device) async {
    final digest = await Hash.sha256.digestBytes(
      _utf8('${device.id}|${device.ecdh}|${device.sign}'),
    );
    return encode(digest.sublist(0, 16));
  }
}
