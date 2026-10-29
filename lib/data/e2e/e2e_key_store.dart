import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webcrypto/webcrypto.dart';

import 'e2e_crypto.dart';
import 'e2e_models.dart';

/// This device's private keys per organisation and user, in Keystore/Keychain.
/// Nothing here returns key bytes or logs them. Sign-out never calls [remove];
/// only an explicit "remove this device" does.
class E2eKeyStore {
  E2eKeyStore();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String _key(String orgId, String userId) =>
      'e2e.device.$orgId.${userId.toLowerCase()}';

  Future<bool> hasDevice(String orgId, String userId) async =>
      await _storage.containsKey(key: _key(orgId, userId));

  Future<E2eDeviceKeys?> load(String orgId, String userId) async {
    final raw = await _storage.read(key: _key(orgId, userId));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return E2eDeviceKeys(
        id: json['id'] as String,
        ecdhPrivate: await EcdhPrivateKey.importPkcs8Key(
          E2eCrypto.decode(json['ecdh'] as String),
          EllipticCurve.p256,
        ),
        signPrivate: await EcdsaPrivateKey.importPkcs8Key(
          E2eCrypto.decode(json['sign'] as String),
          EllipticCurve.p256,
        ),
        ecdhPub: json['ecdhPub'] as String,
        signPub: json['signPub'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String orgId, String userId, E2eDeviceKeys keys) async {
    final value = jsonEncode({
      'id': keys.id,
      'ecdh': E2eCrypto.encode(await keys.ecdhPrivate.exportPkcs8Key()),
      'sign': E2eCrypto.encode(await keys.signPrivate.exportPkcs8Key()),
      'ecdhPub': keys.ecdhPub,
      'signPub': keys.signPub,
    });
    await _storage.write(key: _key(orgId, userId), value: value);
  }

  /// "Remove this device": the only call that deletes the keys.
  Future<void> remove(String orgId, String userId) =>
      _storage.delete(key: _key(orgId, userId));
}
