import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../data/e2e/e2e_crypto.dart';
import '../../data/e2e/e2e_key_store.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/e2e/e2e_random.dart';
import '../../core/config/app_config.dart';
import '../../data/repositories/e2e_repository.dart';
import '../../data/repositories/encryption_policy.dart';
import '../../data/session_store.dart';
import '../../data/socket/socket_service.dart';

class E2eCheck {
  const E2eCheck(this.name, this.isPassed, [this.detail = '']);

  final String name;
  final bool isPassed;
  final String detail;
}

class DebugE2eController extends GetxController {
  DebugE2eController({
    required E2eKeyStore keyStore,
    required this.e2e,
    required this.session,
    required this.socket,
  }) : _keyStore = keyStore;

  static const _vectorsAsset = 'mobile-handoff/e2e-vectors.json';

  final E2eKeyStore _keyStore;
  final E2eRepository e2e;
  final SessionStore session;
  final SocketService socket;
  final _crypto = E2eCrypto();

  final label = TextEditingController(text: 'Connectum mobile (moto g32)');
  final message = ''.obs;
  final isBusy = false.obs;

  /// The destructive buttons need a second tap on the same button.
  final armed = ''.obs;

  final results = <E2eCheck>[].obs;
  final isRunning = false.obs;

  int get passedCount => results.where((r) => r.isPassed).length;
  int get failedCount => results.length - passedCount;
  bool get isAllPassed => results.isNotEmpty && failedCount == 0;

  @override
  void onReady() {
    super.onReady();
    run();
    e2e.refreshStatus();
  }

  @override
  void onClose() {
    label.dispose();
    super.onClose();
  }

  /// Why the server buttons cannot work right now, or null when they can.
  /// Reads the session and socket Rx, so an Obx around it rebuilds.
  String? get blockedReason {
    if (!AppConfig.isConfigured) {
      return 'Server address not set (run with BASE_URL and WS_URL)';
    }
    if (session.current.value == null) return 'Not signed in';
    if (socket.connection.value != SocketState.online) return 'Socket offline';
    return null;
  }

  /// Why Register cannot be tapped, or null. It needs a status read that
  /// succeeded, an encryption mode that is on and a free device slot.
  String? get registerBlockedReason {
    final reason = blockedReason;
    if (reason != null) return reason;
    if (!e2e.isStatusKnown.value) return 'Tap Refresh status first';
    final mode = e2e.mode.value;
    if (mode == 'off') return 'Encryption is off in this organisation';
    if (mode != 'optional' && mode != 'required') {
      return 'Unknown encryption mode "$mode"';
    }
    if (e2e.maxDevices.value > 0 &&
        e2e.myDevices.length >= e2e.maxDevices.value) {
      return 'Device limit reached';
    }
    return null;
  }

  Future<void> refreshDevices() async {
    armed.value = '';
    isBusy.value = true;
    final isOk = await e2e.refreshStatus();
    message.value = isOk ? 'Status refreshed.' : 'Could not read the status.';
    isBusy.value = false;
  }

  /// Registers this phone. Generates keys only when none exist, and asks for
  /// a second tap when keys exist that the server does not know.
  Future<void> register() async {
    if (isBusy.value || registerBlockedReason != null) return;
    if (armed.value != 'register') {
      armed.value = 'register';
      message.value = e2e.hasKeys.value && !e2e.isRegistered
          ? 'Keys exist on this phone but the server does not list this device. '
                'Tap Register again to register those keys.'
          : 'This creates keys on this phone and registers it as a device. '
                'Tap Register again to confirm.';
      return;
    }
    armed.value = '';
    isBusy.value = true;
    final result = await e2e.register(label.text, isConfirmed: true);
    message.value = switch (result) {
      E2eRegisterResult.registered => 'Registered this phone.',
      E2eRegisterResult.alreadyRegistered =>
        'Already registered. Nothing done.',
      E2eRegisterResult.modeOff =>
        'Encryption is off for this organisation. Nothing done.',
      E2eRegisterResult.limitReached =>
        'Device limit reached (${e2e.myDevices.length} of ${e2e.maxDevices.value}). Nothing done.',
      E2eRegisterResult.needsConfirmation => 'Tap Register again to confirm.',
      E2eRegisterResult.needsConnection => 'Needs a connection.',
      E2eRegisterResult.refused => 'Refused: ${e2e.lastError.value}',
    };
    isBusy.value = false;
  }

  Future<void> removeThisDevice() async {
    if (isBusy.value) return;
    if (armed.value != 'remove') {
      armed.value = 'remove';
      message.value =
          'This deletes the keys on this phone and removes only this device '
          'from the server. Old messages stay unreadable. Tap again to confirm.';
      return;
    }
    armed.value = '';
    isBusy.value = true;
    final isOk = await e2e.removeThisDevice();
    message.value = isOk
        ? 'This device was removed and its keys deleted.'
        : 'Not removed: ${e2e.lastError.value}';
    isBusy.value = false;
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
      await _repositoryOpen();
      await _sendChecks();
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

  /// The same path the message list uses: [E2eRepository.open] with a
  /// throwaway sender and reader, no server and no stored keys.
  Future<void> _repositoryOpen() async {
    await _check('repository opens an envelope (throwaway keys)', () async {
      final sender = await _crypto.generateDeviceKeys();
      final reader = await _crypto.generateDeviceKeys();
      final stranger = await _crypto.generateDeviceKeys();
      const text = 'Self-test ✓ héllo';
      final conv = E2eCrypto.dmLabel('selftest-a', 'selftest-b');
      final env = await _crypto.buildEnvelope(
        user: 'selftest-a',
        keys: sender,
        conv: conv,
        recipients: [sender.asPublic, reader.asPublic],
        text: text,
      );
      Future<String?> signKey(String user, String dev) async =>
          user == 'selftest-a' && dev == sender.id ? sender.signPub : null;
      Future<E2eReading> open(E2eDeviceKeys keys, {String? other}) => e2e.open(
        text: env,
        convId: 'dm:selftest-b',
        expectConv: other ?? conv,
        keys: keys,
        signKeyFor: signKey,
      );
      final ok = await open(reader);
      if (ok.state != E2eReadState.ok || ok.text != text) return 'not opened';
      final none = await open(stranger);
      if (none.code != 'not_for_this_device') return 'no wrap not refused';
      final wrong = await open(reader, other: 'dm:selftest-a|selftest-c');
      if (wrong.code != 'wrong_conversation') return 'wrong thread not refused';
      final unknown = await e2e.open(
        text: env,
        convId: 'dm:selftest-b',
        expectConv: conv,
        keys: reader,
        signKeyFor: (_, _) async => null,
      );
      if (unknown.code != 'unknown_sender_device') return 'unknown not refused';
      return null;
    });
  }

  // ---- sending (fake devices only, nothing leaves the phone) ----------------

  Future<void> _sendChecks() async {
    final alice1 = await _crypto.generateDeviceKeys();
    final alice2 = await _crypto.generateDeviceKeys();
    final bob1 = await _crypto.generateDeviceKeys();
    final bob2 = await _crypto.generateDeviceKeys();
    final outsider = await _crypto.generateDeviceKeys();
    final conv = E2eCrypto.dmLabel('alice', 'bob');
    final recipients = [alice1, alice2, bob1, bob2].map((k) => k.asPublic);
    const text = 'Send test ✓ héllo 你好 😀';
    Future<String?> signKey(String user, String dev) async =>
        user == 'alice' && dev == alice1.id ? alice1.signPub : null;
    Future<String> build({String body = text}) => _crypto.buildEnvelope(
      user: 'alice',
      keys: alice1,
      conv: conv,
      recipients: recipients.toList(),
      text: body,
    );
    Future<String?> opens(
      String env,
      E2eDeviceKeys reader, {
      String? expectConv,
    }) async {
      try {
        final opened = await _crypto.openEnvelope(
          text: env,
          keys: reader,
          signKeyFor: signKey,
          expectConv: expectConv ?? conv,
        );
        return opened.text == text ? 'ok' : 'text differs';
      } on E2eException catch (e) {
        return e.code;
      }
    }

    String edit(String env, void Function(Map<String, dynamic> json) change) {
      final json =
          jsonDecode(env.substring(E2eCrypto.prefix.length))
              as Map<String, dynamic>;
      change(json);
      return E2eCrypto.prefix + jsonEncode(json);
    }

    await _check('send: envelope shape and wire line', () async {
      final env = await build();
      final line = '/c m-test /msg bob $env';
      if (!E2eCrypto.isEnvelope(env)) return 'no prefix';
      if (env.contains('\n') || env.contains(' ')) return 'not one token';
      if (env.codeUnits.any((c) => c > 126)) return 'not ascii';
      if (env.length > 120000) return 'over the server cap';
      if (line.split(' ').length != 5) return 'line splits wrongly';
      final json =
          jsonDecode(env.substring(E2eCrypto.prefix.length))
              as Map<String, dynamic>;
      final keys = json['keys'] as Map;
      if (keys.length != 4) return 'expected 4 wraps, got ${keys.length}';
      if (!keys.containsKey(alice2.id)) return 'my other device left out';
      if (json['dev'] != alice1.id || json['from'] != 'alice') return 'sender';
      if (json['ts'] is! int) return 'ts is not an integer';
      for (final f in ['mid', 'ek', 'iv', 'ct', 'sig']) {
        if ((json[f] as String).contains('=')) return '$f has padding';
      }
      return (json['mid'] as String).length == 22 ? null : 'mid length';
    });
    await _check('send: sender device and peer devices open it', () async {
      final env = await build();
      for (final reader in [alice1, alice2, bob1, bob2]) {
        final r = await opens(env, reader);
        if (r != 'ok') return r;
      }
      return null;
    });
    await _check('send: a device outside the list cannot open it', () async {
      final r = await opens(await build(), outsider);
      return r == 'not_for_this_device' ? null : 'got $r';
    });
    await _check('send: two messages share nothing random', () async {
      final a = jsonDecode((await build()).substring(5)) as Map;
      final b = jsonDecode((await build()).substring(5)) as Map;
      for (final f in ['mid', 'ek', 'iv', 'ct']) {
        if (a[f] == b[f]) return '$f repeated';
      }
      return null;
    });
    await _check('send: long text and padding edge', () async {
      for (final n in [1, 59, 60, 64, 2000]) {
        final body = 'x' * n;
        final env = await build(body: body);
        final opened = await _crypto.openEnvelope(
          text: env,
          keys: bob2,
          signKeyFor: signKey,
          expectConv: conv,
        );
        if (opened.text != body) return 'length $n differs';
      }
      return null;
    });
    await _check('send: tampering is refused', () async {
      final env = await build();
      Future<String?> expect(String name, String bad, String code) async {
        final got = await opens(bad, bob1);
        return got == code ? null : '$name: got $got, want $code';
      }

      final cases = <(String, String, String)>[
        (
          'ciphertext',
          edit(env, (j) => j['ct'] = _flip(j['ct'] as String)),
          'bad_signature',
        ),
        (
          'timestamp',
          edit(env, (j) => j['ts'] = (j['ts'] as int) + 1),
          'bad_signature',
        ),
        (
          'conversation',
          edit(env, (j) => j['conv'] = 'dm:alice|carol'),
          'wrong_conversation',
        ),
        (
          'sender name',
          edit(env, (j) => j['from'] = 'mallory'),
          'unknown_sender_device',
        ),
        (
          'signature',
          edit(env, (j) => j['sig'] = _flip(j['sig'] as String)),
          'bad_signature',
        ),
        (
          'my wrap removed',
          edit(env, (j) => (j['keys'] as Map).remove(bob1.id)),
          'not_for_this_device',
        ),
        (
          'my wrap altered',
          edit(env, (j) {
            final w = (j['keys'] as Map)[bob1.id] as Map;
            w['w'] = _flip(w['w'] as String);
          }),
          'decrypt_failed',
        ),
        (
          'wrap moved to another device',
          edit(env, (j) {
            final k = j['keys'] as Map;
            k[bob1.id] = k[bob2.id];
          }),
          'decrypt_failed',
        ),
      ];
      for (final c in cases) {
        final problem = await expect(c.$1, c.$2, c.$3);
        if (problem != null) return problem;
      }
      return null;
    });
    await _check('send: a signature from another device is refused', () async {
      final forged = await _crypto.buildEnvelope(
        user: 'alice',
        keys: alice2,
        conv: conv,
        recipients: recipients.toList(),
        text: text,
      );
      // Claims to come from device alice1 but is signed with alice2's key.
      final claimed = edit(forged, (j) => j['dev'] = alice1.id);
      final r = await opens(claimed, bob1);
      return r == 'bad_signature' ? null : 'got $r';
    });

    _policyChecks(alice1, alice2.asPublic, bob1.asPublic);
  }

  String _flip(String b64) {
    final first = b64.codeUnitAt(0);
    return String.fromCharCode(first == 0x41 ? 0x42 : 0x41) + b64.substring(1);
  }

  /// The one rule for "plain, encrypt or blocked", on made-up inputs.
  void _policyChecks(
    E2eDeviceKeys mine,
    E2eDevicePublic otherOfMine,
    E2eDevicePublic peer,
  ) {
    E2eSendVerdict verdict({
      String? mode = 'optional',
      bool isEncryptedThread = false,
      List<E2eDevicePublic>? peerDevices,
      List<E2eDevicePublic>? myDevices,
      E2eDeviceKeys? keys,
      List<E2ePinChange> pinChanges = const [],
      bool hasKeys = true,
    }) => EncryptionPolicy.decide(
      mode: mode,
      peer: 'bob',
      isEncryptedThread: isEncryptedThread,
      peerDevices: peerDevices ?? [peer],
      myDevices: myDevices ?? [mine.asPublic, otherOfMine],
      keys: hasKeys ? (keys ?? mine) : null,
      pinChanges: pinChanges,
    ).verdict;
    void expect(String name, E2eSendVerdict got, E2eSendVerdict want) => _add(
      'policy: $name',
      got == want,
      got == want ? '' : 'got ${got.name}',
    );

    expect('mode off sends plain', verdict(mode: 'off'), E2eSendVerdict.plain);
    expect(
      'mode off ignores a peer with devices',
      verdict(mode: 'off', isEncryptedThread: true),
      E2eSendVerdict.plain,
    );
    expect('unknown mode waits', verdict(mode: null), E2eSendVerdict.unknown);
    expect('peer with a device encrypts', verdict(), E2eSendVerdict.encrypt);
    expect(
      'required mode, peer with a device',
      verdict(mode: 'required'),
      E2eSendVerdict.encrypt,
    );
    expect(
      'optional, peer without devices, no history: plain',
      verdict(peerDevices: []),
      E2eSendVerdict.plain,
    );
    expect(
      'optional, peer without devices, encrypted history: blocked',
      verdict(peerDevices: [], isEncryptedThread: true),
      E2eSendVerdict.blocked,
    );
    expect(
      'required, peer without devices: blocked',
      verdict(mode: 'required', peerDevices: []),
      E2eSendVerdict.blocked,
    );
    expect(
      'this phone not registered: blocked, not plain',
      verdict(myDevices: [otherOfMine]),
      E2eSendVerdict.blocked,
    );
    expect(
      'no keys on this phone: blocked, not plain',
      verdict(hasKeys: false),
      E2eSendVerdict.blocked,
    );
    final changed = EncryptionPolicy.decide(
      mode: 'optional',
      peer: 'bob',
      isEncryptedThread: false,
      peerDevices: [peer],
      myDevices: [mine.asPublic],
      keys: mine,
      pinChanges: [E2ePinChange(user: 'bob', device: peer)],
    );
    _add(
      'policy: a changed key blocks and offers a review',
      changed.isBlocked && changed.isKeyChange && changed.recipients.isEmpty,
    );
    final sent = EncryptionPolicy.decide(
      mode: 'optional',
      peer: 'bob',
      isEncryptedThread: false,
      peerDevices: [peer],
      myDevices: [mine.asPublic, otherOfMine],
      keys: mine,
      pinChanges: const [],
    );
    _add(
      'policy: recipients are the peer and all my devices',
      sent.recipients.length == 3 &&
          sent.recipients.any((d) => d.id == mine.id) &&
          sent.recipients.any((d) => d.id == otherOfMine.id),
    );

    const pin = (ecdh: 'E1', sign: 'S1');
    const same = E2eDevicePublic(id: 'd1', ecdh: 'E1', sign: 'S1');
    const other = E2eDevicePublic(id: 'd1', ecdh: 'E2', sign: 'S1');
    const newId = E2eDevicePublic(id: 'd2', ecdh: 'E9', sign: 'S9');
    _add(
      'pins: same key passes, other key or sign is a change, a new id is not',
      E2eRepository.pinMismatches({'d1': pin}, [same, newId]).isEmpty &&
          E2eRepository.pinMismatches({'d1': pin}, [other]).length == 1 &&
          E2eRepository.pinMismatches(
                {'d1': pin},
                [const E2eDevicePublic(id: 'd1', ecdh: 'E1', sign: 'S2')],
              ).length ==
              1,
    );
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
