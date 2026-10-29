import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/e2e/e2e_crypto.dart';
import '../../data/e2e/e2e_key_store.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/e2e/e2e_random.dart';

class E2eCheck {
  const E2eCheck(this.name, this.isPassed, [this.detail = '']);

  final String name;
  final bool isPassed;
  final String detail;
}

class DebugE2eController extends GetxController {
  DebugE2eController({required E2eKeyStore keyStore}) : _keyStore = keyStore;

  static const _vectorsAsset = 'mobile-handoff/e2e-vectors.json';

  final E2eKeyStore _keyStore;
  final _crypto = E2eCrypto();

  final results = <E2eCheck>[].obs;
  final isRunning = false.obs;

  int get passedCount => results.where((r) => r.isPassed).length;
  int get failedCount => results.length - passedCount;
  bool get isAllPassed => results.isNotEmpty && failedCount == 0;

  @override
  void onReady() {
    super.onReady();
    run();
  }

  Future<void> run() async {
    if (isRunning.value) return;
    isRunning.value = true;
    results.clear();
    try {
      final vectors =
          jsonDecode(await rootBundle.loadString(_vectorsAsset))
              as Map<String, dynamic>;
      final devices = await _importDevices(vectors);
      await _envelopes(vectors, devices);
      await _negatives(vectors, devices);
      await _registration(vectors, devices);
      await _file(vectors);
      await _safety(vectors, devices);
      _encodings(vectors);
      await _roundTrip();
      await _keyStoreRoundTrip();
    } catch (e) {
      _add('self-test aborted', false, e.runtimeType.toString());
    } finally {
      isRunning.value = false;
    }
  }

  void _add(String name, bool isPassed, [String detail = '']) =>
      results.add(E2eCheck(name, isPassed, detail));

  Future<void> _check(String name, Future<String?> Function() body) async {
    try {
      final problem = await body();
      _add(name, problem == null, problem ?? '');
    } on E2eException catch (e) {
      _add(name, false, 'threw ${e.code}');
    } catch (e) {
      _add(name, false, 'threw ${e.runtimeType}');
    }
  }

  Uint8List _hex(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // ---- devices ----------------------------------------------------------

  Future<Map<String, _Device>> _importDevices(
    Map<String, dynamic> vectors,
  ) async {
    final out = <String, _Device>{};
    await _check('import fixed test keys', () async {
      for (final d in vectors['devices'] as List) {
        final map = d as Map<String, dynamic>;
        final keys = await _crypto.importDeviceKeys(
          id: map['id'] as String,
          ecdhScalar: _hex(map['ecdhPrivateScalarHex'] as String),
          signScalar: _hex(map['signPrivateScalarHex'] as String),
          ecdhPub: map['ecdhPublic'] as String,
          signPub: map['signPublic'] as String,
        );
        out[keys.id] = _Device(map['user'] as String, keys);
      }
      return out.length == 5 ? null : 'expected 5 devices';
    });
    return out;
  }

  Future<String?> _signKeyFor(
    Map<String, _Device> devices,
    String user,
    String dev,
  ) async {
    final d = devices[dev];
    return d != null && d.user == user ? d.keys.signPub : null;
  }

  // ---- envelopes --------------------------------------------------------

  Future<void> _envelopes(
    Map<String, dynamic> vectors,
    Map<String, _Device> devices,
  ) async {
    final list = vectors['envelopes'] as List;
    for (var i = 0; i < list.length; i++) {
      final v = list[i] as Map<String, dynamic>;
      final n = i + 1;
      final text = v['envelope'] as String;
      final conv = v['conv'] as String;
      final expected = v['plaintextText'] as String;
      final recipients = (v['decryptsTo'] as Map<String, dynamic>).keys;
      final sender = devices[v['sender'] as String]!;
      final e = _crypto.parseEnvelope(text);

      await _check(
        'envelope $n: decrypt on ${recipients.length} devices',
        () async {
          for (final id in recipients) {
            final opened = await _crypto.openEnvelope(
              text: text,
              keys: devices[id]!.keys,
              signKeyFor: (u, d) => _signKeyFor(devices, u, d),
              expectConv: conv,
            );
            if (opened.text != expected) return 'plaintext differs on a device';
            if (opened.from != sender.user || opened.dev != sender.keys.id) {
              return 'sender differs';
            }
          }
          return null;
        },
      );

      await _check('envelope $n: signature verifies', () async {
        final ok = await _crypto.verify(
          signPub: sender.keys.signPub,
          signature: e.sig,
          data: utf8.encode(
            E2eCrypto.signatureInput(
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
        return ok ? null : 'does not verify';
      });

      await _check('envelope $n: encrypting reproduces it', () async {
        final random = v['random'] as Map<String, dynamic>;
        final wrapIvs = random['wrapIvsHex'] as Map<String, dynamic>;
        final built =
            await E2eCrypto(
              random: E2eRandom.fixed([
                _hex(random['midBytesHex'] as String),
                _hex(random['messageKeyHex'] as String),
                _hex(random['ivHex'] as String),
                (
                  scalar: _hex(random['ephemeralPrivateScalarHex'] as String),
                  publicPoint: E2eCrypto.decode(e.ek),
                ),
                for (final id in wrapIvs.keys) _hex(wrapIvs[id] as String),
              ]),
            ).buildEnvelope(
              user: sender.user,
              keys: sender.keys,
              conv: conv,
              recipients: [
                for (final id in wrapIvs.keys) devices[id]!.keys.asPublic,
              ],
              text: expected,
              ts: v['ts'] as int,
            );
        final b = _crypto.parseEnvelope(built);
        final same =
            b.mid == e.mid &&
            b.ek == e.ek &&
            b.iv == e.iv &&
            b.ct == e.ct &&
            b.from == e.from &&
            b.dev == e.dev &&
            b.conv == e.conv &&
            b.ts == e.ts &&
            jsonEncode(b.keys) == jsonEncode(e.keys);
        if (!same) return 'fields differ';
        final ok = await _crypto.verify(
          signPub: sender.keys.signPub,
          signature: b.sig,
          data: utf8.encode(
            E2eCrypto.signatureInput(
              mid: b.mid,
              from: b.from,
              dev: b.dev,
              conv: b.conv,
              ts: b.ts,
              ek: b.ek,
              iv: b.iv,
              ct: b.ct,
            ),
          ),
        );
        return ok ? null : 'own signature does not verify';
      });
    }
  }

  // ---- failure cases ----------------------------------------------------

  Future<void> _negatives(
    Map<String, dynamic> vectors,
    Map<String, _Device> devices,
  ) async {
    for (final item in vectors['negative'] as List) {
      final v = item as Map<String, dynamic>;
      final name = v['case'] as String;
      final expectedCode = v['expectError'] as String;
      final opener = devices[v['openAs'] as String]!;
      final e = _crypto.parseEnvelope(v['envelope'] as String);
      // The vectors do not record which sender key or conversation each case
      // used: the sender's own key and the DM label, except where the case
      // says otherwise.
      final isWrongKey = name.startsWith('wrong signing key');
      final expectConv = name.startsWith('conv modified')
          ? null
          : (v['expectConvArg'] as String?) ?? 'dm:alice|bob';
      String code;
      try {
        await _crypto.openEnvelope(
          text: v['envelope'] as String,
          keys: opener.keys,
          signKeyFor: (user, dev) async => isWrongKey
              ? opener.keys.signPub
              : (await _signKeyFor(devices, user, dev)) ??
                    devices.values
                        .firstWhere((d) => d.user == e.from)
                        .keys
                        .signPub,
          expectConv: expectConv,
        );
        code = 'opened';
      } on E2eException catch (ex) {
        code = ex.code;
      } catch (ex) {
        code = ex.runtimeType.toString();
      }
      _add(
        'fails: $name',
        code == expectedCode,
        code == expectedCode ? expectedCode : 'got $code, want $expectedCode',
      );
    }
  }

  // ---- registration proof ----------------------------------------------

  Future<void> _registration(
    Map<String, dynamic> vectors,
    Map<String, _Device> devices,
  ) async {
    final reg = vectors['registration'] as Map<String, dynamic>;
    final args =
        (reg['rpcExample'] as Map<String, dynamic>)['args']
            as Map<String, dynamic>;
    final device = devices[args['id'] as String]!;
    await _check('registration: vector proof verifies', () async {
      final message = E2eCrypto.registrationMessage(
        user: device.user,
        id: device.keys.id,
        ecdhPub: device.keys.ecdhPub,
        signPub: device.keys.signPub,
      );
      if (message != reg['message']) return 'message differs';
      final ok = await _crypto.verifyRegistrationProof(
        user: device.user,
        id: device.keys.id,
        ecdhPub: device.keys.ecdhPub,
        signPub: device.keys.signPub,
        proof: reg['proofB64u'] as String,
      );
      return ok ? null : 'does not verify';
    });
    await _check('registration: own proof verifies', () async {
      final proof = await _crypto.registrationProof(
        user: device.user,
        keys: device.keys,
      );
      final ok = await _crypto.verifyRegistrationProof(
        user: device.user,
        id: device.keys.id,
        ecdhPub: device.keys.ecdhPub,
        signPub: device.keys.signPub,
        proof: proof,
      );
      return ok && E2eCrypto.decode(proof).length == 64 ? null : 'bad proof';
    });
  }

  // ---- file -------------------------------------------------------------

  Future<void> _file(Map<String, dynamic> vectors) async {
    final f = vectors['file'] as Map<String, dynamic>;
    final plain = _hex(f['plaintextHex'] as String);
    final cipher = _hex(f['ciphertextWithTagHex'] as String);
    await _check('file: decrypt', () async {
      final out = await _crypto.decryptFile(
        cipher,
        f['keyB64u'] as String,
        f['ivB64u'] as String,
      );
      return _toHex(out) == _toHex(plain) ? null : 'plaintext differs';
    });
    await _check('file: encrypting reproduces it', () async {
      final enc = await E2eCrypto(
        random: E2eRandom.fixed([
          E2eCrypto.decode(f['keyB64u'] as String),
          E2eCrypto.decode(f['ivB64u'] as String),
        ]),
      ).encryptFile(plain);
      return _toHex(enc.ciphertext) == _toHex(cipher) ? null : 'differs';
    });
    await _check('file: tampered data is refused', () async {
      final bad = Uint8List.fromList(cipher)..[0] ^= 1;
      try {
        await _crypto.decryptFile(
          bad,
          f['keyB64u'] as String,
          f['ivB64u'] as String,
        );
        return 'opened';
      } on E2eException catch (e) {
        return e.code == 'file_decrypt_failed' ? null : 'got ${e.code}';
      }
    });
  }

  // ---- safety number, fingerprint --------------------------------------

  Future<void> _safety(
    Map<String, dynamic> vectors,
    Map<String, _Device> devices,
  ) async {
    final ids = vectors['devices'] as List;
    E2eDevicePublic pub(String user, int nth) => devices.values
        .where((d) => d.user == user)
        .elementAt(nth)
        .keys
        .asPublic;
    assert(ids.isNotEmpty);
    await _check('safety number', () async {
      final value = await _crypto.safetyNumber(
        [pub('alice', 0), pub('alice', 1)],
        [pub('bob', 0)],
      );
      final swapped = await _crypto.safetyNumber(
        [pub('bob', 0)],
        [pub('alice', 1), pub('alice', 0)],
      );
      final expected =
          (vectors['safetyNumber'] as Map<String, dynamic>)['value'];
      return value == expected && swapped == expected
          ? null
          : 'does not match the vector';
    });
    await _check('device fingerprint', () async {
      final value = await _crypto.deviceFingerprint(pub('alice', 0));
      final expected =
          (vectors['deviceFingerprint'] as Map<String, dynamic>)['value'];
      return value == expected ? null : 'does not match the vector';
    });
  }

  void _encodings(Map<String, dynamic> vectors) {
    final b = vectors['base64url'] as Map<String, dynamic>;
    final isEncodingOk =
        E2eCrypto.encode(const <int>[]) == b['enc_empty'] &&
        E2eCrypto.encode(const [0xfb, 0xff]) == b['enc_ff'] &&
        E2eCrypto.encode(const [1]) == b['enc_1byte'];
    _add('base64url: encode', isEncodingOk);
    String code;
    try {
      E2eCrypto.decode('AQ==');
      code = 'accepted';
    } on E2eException catch (e) {
      code = e.code;
    }
    _add('base64url: padding refused', code == b['decodeRejectsPadding'], code);
  }

  // ---- fresh keys -------------------------------------------------------

  Future<void> _roundTrip() async {
    await _check('round trip with fresh keys', () async {
      final a1 = await _crypto.generateDeviceKeys();
      final a2 = await _crypto.generateDeviceKeys();
      final b1 = await _crypto.generateDeviceKeys();
      final stranger = await _crypto.generateDeviceKeys();
      const text = 'héllo ✓ 你好 😀';
      final conv = E2eCrypto.dmLabel('Bob', 'alice');
      if (conv != 'dm:alice|bob') return 'conversation label';
      final env = await _crypto.buildEnvelope(
        user: 'alice',
        keys: a1,
        conv: conv,
        recipients: [a1.asPublic, a2.asPublic, b1.asPublic],
        text: text,
      );
      Future<String?> signKey(String user, String dev) async =>
          user == 'alice' && dev == a1.id ? a1.signPub : null;
      for (final reader in [a1, a2, b1]) {
        final opened = await _crypto.openEnvelope(
          text: env,
          keys: reader,
          signKeyFor: signKey,
          expectConv: conv,
        );
        if (opened.text != text) return 'plaintext differs';
      }
      try {
        await _crypto.openEnvelope(
          text: env,
          keys: stranger,
          signKeyFor: signKey,
        );
        return 'a device without a wrap opened it';
      } on E2eException catch (e) {
        return e.code == 'not_for_this_device' ? null : 'got ${e.code}';
      }
    });
  }

  Future<void> _keyStoreRoundTrip() async {
    const org = 'debug-e2e';
    const user = 'selftest';
    await _check('key store round trip (throwaway keys)', () async {
      final keys = await _crypto.generateDeviceKeys();
      await _keyStore.save(org, user, keys);
      final loaded = await _keyStore.load(org, user);
      await _keyStore.remove(org, user);
      if (loaded == null || loaded.id != keys.id) return 'not loaded';
      if (await _keyStore.hasDevice(org, user)) return 'not removed';
      final proof = await _crypto.registrationProof(user: user, keys: loaded);
      final ok = await _crypto.verifyRegistrationProof(
        user: user,
        id: keys.id,
        ecdhPub: keys.ecdhPub,
        signPub: keys.signPub,
        proof: proof,
      );
      return ok ? null : 'loaded key does not sign correctly';
    });
  }
}

class _Device {
  const _Device(this.user, this.keys);

  final String user;
  final E2eDeviceKeys keys;
}
