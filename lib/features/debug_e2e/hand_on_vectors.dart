import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

import '../../data/e2e/e2e_crypto.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/e2e/e2e_random.dart';
import '../../data/e2e/hand_on.dart';
import '../../data/e2e/hand_on_job.dart';
import '../../data/socket/socket_service.dart';

/// The self-test of the older-device hand-on. No server, no storage: the
/// backend's `rewrap` vectors (`assets/debug/e2e-rewrap-vectors.json`, the
/// `rewrap` section of the backend file) and a stand-in server for the job.
class HandOnVectors {
  HandOnVectors(this._check);

  final Future<void> Function(String name, Future<String?> Function() body)
  _check;

  Future<void> run(Map<String, dynamic> vectors) async {
    await _rewrap(vectors);
    await _page(vectors);
    await _batching();
    await _pacing();
    await _errors();
    await _job();
    await _small();
  }

  // ---- the backend's rewrap vectors --------------------------------------

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Future<EcdhPrivateKey> _ecdh(String pkcs8) => EcdhPrivateKey.importPkcs8Key(
    E2eCrypto.decode(pkcs8),
    EllipticCurve.p256,
  );

  ({Uint8List scalar, Uint8List publicPoint}) _ephemeral(Map fixed) {
    final jwk = fixed['ephPrivateJwk'] as Map;
    return (
      scalar: E2eCrypto.decode(jwk['d'] as String),
      publicPoint: Uint8List.fromList([
        4,
        ...E2eCrypto.decode(jwk['x'] as String),
        ...E2eCrypto.decode(jwk['y'] as String),
      ]),
    );
  }

  Future<void> _rewrap(Map<String, dynamic> vectors) async {
    final signPub = vectors['senderSignPub'] as String;
    final positive = vectors['positive'] as List;
    for (var i = 0; i < positive.length; i++) {
      final v = positive[i] as Map<String, dynamic>;
      final name = 'rewrap ${i + 1} (${v['name']})';
      final input = v['input'] as Map<String, dynamic>;
      final expected = v['expected'] as Map<String, dynamic>;
      final older = input['olderDevice'] as Map;
      final target = input['target'] as Map;
      final fixed = input['fixed'] as Map;
      final envelopeText = input['envelope'] as String;

      await _check('$name: the box equals the vector byte for byte', () async {
        final crypto = E2eCrypto(
          random: E2eRandom.fixed([
            _ephemeral(fixed),
            Uint8List.fromList(E2eCrypto.decode(fixed['iv'] as String)),
          ]),
        );
        final item = await crypto.rewrap(
          e: crypto.parseEnvelope(envelopeText),
          deviceId: older['id'] as String,
          ecdhPrivate: await _ecdh(older['ecdhPkcs8'] as String),
          target: E2eDevicePublic(
            id: target['id'] as String,
            ecdh: target['ecdh'] as String,
            sign: '',
          ),
        );
        final want = (expected['item'] as Map).cast<String, String>();
        for (final key in ['mid', 'iv', 'w', 'ek']) {
          if (item[key] != want[key]) return '$key differs';
        }
        return item.length == 4 ? null : 'extra fields';
      });

      await _check('$name: the message key matches', () async {
        final crypto = E2eCrypto();
        final key = await crypto.unwrapOwnBox(
          e: crypto.parseEnvelope(envelopeText),
          deviceId: older['id'] as String,
          ecdhPrivate: await _ecdh(older['ecdhPkcs8'] as String),
        );
        final inter = expected['intermediates'] as Map;
        return _hex(key) == inter['msgKeyHex'] ? null : 'key differs';
      });

      await _check('$name: the device it is for opens the message', () async {
        final crypto = E2eCrypto();
        final waiting = EcdsaPrivateKey.generateKey(EllipticCurve.p256);
        final keys = E2eDeviceKeys(
          id: target['id'] as String,
          ecdhPrivate: await _ecdh(input['targetEcdhPkcs8'] as String),
          signPrivate: (await waiting).privateKey,
          ecdhPub: target['ecdh'] as String,
          signPub: '',
        );
        final opened = await crypto.openEnvelope(
          text: expected['envelopeWithBox'] as String,
          keys: keys,
          signKeyFor: (user, dev) async => signPub,
          expectConv: vectors['expectConv'] as String,
        );
        return opened.text.isEmpty ? 'empty text' : null;
      });
    }

    final negative = vectors['negative'] as List;
    for (final n in negative) {
      final v = n as Map<String, dynamic>;
      final failsAt = v['expectFailsAt'] as String;
      final code = switch (failsAt) {
        '2 conversation' => 'wrong_conversation',
        '3 box for this device' => 'not_for_this_device',
        _ => 'decrypt_failed',
      };
      await _check('rewrap refuses: ${v['name']}', () async {
        final crypto = E2eCrypto();
        final keys = E2eDeviceKeys(
          id: v['deviceId'] as String,
          ecdhPrivate: await _ecdh(v['ecdhPkcs8'] as String),
          signPrivate: (await EcdsaPrivateKey.generateKey(
            EllipticCurve.p256,
          )).privateKey,
          ecdhPub: '',
          signPub: '',
        );
        try {
          await crypto.openEnvelope(
            text: v['envelope'] as String,
            keys: keys,
            signKeyFor: (user, dev) async => signPub,
            expectConv: v['expectConv'] as String,
          );
          return 'was opened';
        } on E2eException catch (e) {
          return e.code == code ? null : 'got ${e.code}, want $code';
        }
      });
    }

    final first = positive.first['input'] as Map;
    final older = first['olderDevice'] as Map;
    await _check('rewrap: no box for this device is refused', () async {
      final crypto = E2eCrypto();
      final json =
          jsonDecode((first['envelope'] as String).substring(5))
              as Map<String, dynamic>;
      (json['keys'] as Map).remove(older['id']);
      final noBox = 'e2e1:${jsonEncode(json)}';
      try {
        await crypto.rewrap(
          e: crypto.parseEnvelope(noBox),
          deviceId: older['id'] as String,
          ecdhPrivate: await _ecdh(older['ecdhPkcs8'] as String),
          target: E2eDevicePublic(
            id: (first['target'] as Map)['id'] as String,
            ecdh: (first['target'] as Map)['ecdh'] as String,
            sign: '',
          ),
        );
        return 'was rewrapped';
      } on E2eException catch (e) {
        return e.code == 'not_for_this_device' ? null : 'got ${e.code}';
      }
    });
    await _check('rewrap: a changed box is refused', () async {
      final crypto = E2eCrypto();
      final json =
          jsonDecode((first['envelope'] as String).substring(5))
              as Map<String, dynamic>;
      final box = (json['keys'] as Map)[older['id']] as Map;
      final w = E2eCrypto.decode(box['w'] as String);
      w[0] ^= 1;
      box['w'] = E2eCrypto.encode(w);
      try {
        await crypto.rewrap(
          e: crypto.parseEnvelope('e2e1:${jsonEncode(json)}'),
          deviceId: older['id'] as String,
          ecdhPrivate: await _ecdh(older['ecdhPkcs8'] as String),
          target: E2eDevicePublic(
            id: (first['target'] as Map)['id'] as String,
            ecdh: (first['target'] as Map)['ecdh'] as String,
            sign: '',
          ),
        );
        return 'was rewrapped';
      } on E2eException catch (e) {
        return e.code == 'decrypt_failed' ? null : 'got ${e.code}';
      }
    });
  }

  /// The page worker: skips what already has a box, counts what it cannot
  /// open, and what it makes opens on the target (random keys this time).
  Future<void> _page(Map<String, dynamic> vectors) async {
    final first = (vectors['positive'] as List).first['input'] as Map;
    final older = first['olderDevice'] as Map;
    final target = first['target'] as Map;
    final withBox =
        ((vectors['positive'] as List).first['expected']
                as Map)['envelopeWithBox']
            as String;
    final work = HandOnWork(
      ecdhPkcs8: E2eCrypto.decode(older['ecdhPkcs8'] as String),
      deviceId: older['id'] as String,
      targetId: target['id'] as String,
      targetEcdh: target['ecdh'] as String,
      texts: [first['envelope'] as String, withBox, 'not an envelope'],
    );
    await _check('page: one made, one already there, one skipped', () async {
      final r = await handOnRewrapPage(work);
      if (r.items.length != 1) return '${r.items.length} boxes';
      if (r.already != 1) return 'already ${r.already}';
      if (r.skipped != 1) return 'skipped ${r.skipped}';
      final json =
          jsonDecode((first['envelope'] as String).substring(5))
              as Map<String, dynamic>;
      (json['keys'] as Map)[target['id']] = {
        'iv': r.items.first['iv'],
        'w': r.items.first['w'],
        'ek': r.items.first['ek'],
      };
      final crypto = E2eCrypto();
      final keys = E2eDeviceKeys(
        id: target['id'] as String,
        ecdhPrivate: await _ecdh(first['targetEcdhPkcs8'] as String),
        signPrivate: (await EcdsaPrivateKey.generateKey(
          EllipticCurve.p256,
        )).privateKey,
        ecdhPub: '',
        signPub: '',
      );
      final opened = await crypto.openEnvelope(
        text: 'e2e1:${jsonEncode(json)}',
        keys: keys,
        signKeyFor: (user, dev) async => vectors['senderSignPub'] as String,
      );
      return opened.text.isEmpty ? 'empty' : null;
    });
    await _check('page: a fresh one-time key each time', () async {
      final a = await handOnRewrapPage(work);
      final b = await handOnRewrapPage(work);
      return a.items.first['ek'] != b.items.first['ek'] ? null : 'same ek';
    });
    await _check('page: the same result on a worker isolate', () async {
      final r = await handOnRewrapInIsolate(work);
      return r.items.length == 1 && r.already == 1 && r.skipped == 1
          ? null
          : 'differs';
    });
  }

  // ---- batching ------------------------------------------------------------

  Future<void> _batching() async {
    List<int> sizes(int n) => HandOnBatcher.split(
      List.generate(n, (i) => i),
    ).map((b) => b.length).toList();
    for (final (n, want) in [
      (0, <int>[]),
      (1, [1]),
      (399, [399]),
      (400, [400]),
      (401, [400, 1]),
      (800, [400, 400]),
      (1000, [400, 400, 200]),
      (1300, [400, 400, 400, 100]),
    ]) {
      await _check('batches: $n boxes', () async {
        final got = sizes(n);
        return got.join(',') == want.join(',') ? null : 'got ${got.join(',')}';
      });
    }
    await _check('batches: nothing lost, nothing twice, in order', () async {
      final all = List.generate(1234, (i) => i);
      final flat = HandOnBatcher.split(all).expand((b) => b).toList();
      return flat.length == 1234 &&
              [for (var i = 0; i < 1234; i++) i].every((i) => flat[i] == i)
          ? null
          : 'changed';
    });
    await _check('batches: never above the server limit', () async {
      return HandOnLimits.batchSize <= HandOnLimits.serverMaxItems &&
              HandOnLimits.batchSize == 400
          ? null
          : 'batch ${HandOnLimits.batchSize}';
    });
  }

  // ---- pacing ----------------------------------------------------------------

  Future<void> _pacing() async {
    var now = DateTime(2026, 11, 4, 12);
    final pacer = HandOnPacer(now: () => now);
    await _check('pacing: puts wait once the budget is used', () async {
      final budget = HandOnLimits.budgets['e2e.sync.put']!;
      for (var i = 0; i < budget; i++) {
        if (pacer.waitFor('e2e.sync.put') != Duration.zero) return 'early wait';
        pacer.record('e2e.sync.put');
      }
      return pacer.waitFor('e2e.sync.put') == HandOnLimits.window
          ? null
          : 'wait ${pacer.waitFor('e2e.sync.put')}';
    });
    await _check('pacing: the wait ends as the window moves', () async {
      now = now.add(const Duration(minutes: 4));
      final left = pacer.waitFor('e2e.sync.put');
      now = now.add(left);
      return pacer.waitFor('e2e.sync.put') == Duration.zero &&
              left == const Duration(minutes: 6)
          ? null
          : 'left $left';
    });
    await _check('pacing: below the server limits and apart', () async {
      const server = {
        'e2e.sync.put': 400,
        'e2e.sync.page': 600,
        'e2e.devices': 600,
        'e2e.sync.approved': 60,
      };
      for (final e in server.entries) {
        if (HandOnLimits.budgets[e.key]! >= e.value) return '${e.key} at limit';
      }
      final a = HandOnPacer(now: () => now);
      for (var i = 0; i < HandOnLimits.budgets['e2e.sync.put']!; i++) {
        a.record('e2e.sync.put');
      }
      return a.waitFor('e2e.sync.page') == Duration.zero ? null : 'shared';
    });
    await _check(
      'pacing: rate_limited waits 5, 10, 20, 40, 60, 60 s',
      () async {
        final got = [
          for (var i = 0; i < 6; i++) HandOnPacer.backoff(i).inSeconds,
        ];
        return got.join(',') == '5,10,20,40,60,60' ? null : got.join(',');
      },
    );
  }

  // ---- error mapping -----------------------------------------------------------

  Future<void> _errors() async {
    const table = [
      ('rate_limited', HandOnFailureKind.rateLimited, true),
      ('not_waiting', HandOnFailureKind.anotherFinished, false),
      ('not_found', HandOnFailureKind.deviceGone, false),
      ('invalid', HandOnFailureKind.rejected, true),
      ('session_replaced', HandOnFailureKind.sessionEnded, false),
      ('session_expired', HandOnFailureKind.sessionEnded, false),
      ('forbidden', HandOnFailureKind.notAllowed, false),
      ('something_new', HandOnFailureKind.unknown, true),
    ];
    for (final (code, kind, retry) in table) {
      await _check('error $code -> ${kind.name}', () async {
        final f = HandOnFailure.fromCode(code);
        if (f.kind != kind) return 'kind ${f.kind.name}';
        if (f.isRetryable != retry) return 'retryable ${f.isRetryable}';
        return f.message.isEmpty ? 'no text' : null;
      });
    }
    await _check('error texts are the docs\' words', () async {
      final ok =
          HandOnFailure.fromCode('rate_limited').message ==
              'Too many history uploads; try again in a moment.' &&
          HandOnFailure.fromCode('not_waiting').message ==
              'That device is not waiting for its earlier messages.' &&
          HandOnFailure.replacedText ==
              'You were signed out because this account signed in on another tab or device.' &&
          HandOnFailure.expiredText ==
              'Your session has ended. Please sign in again.';
      return ok ? null : 'text changed';
    });
  }

  // ---- the job against a stand-in server ---------------------------------------

  Future<void> _job() async {
    await _check('job: 1,300 boxes, puts of 400 at most, done once', () async {
      final s = _FakeServer(pageSizes: [650, 650]);
      await s.job().run();
      if (s.putSizes.any((n) => n > 400)) return 'a put above 400';
      if (s.putSizes.join(',') != '400,250,400,250') {
        return 'puts ${s.putSizes.join(',')}';
      }
      if (s.stored.length != 1300 || s.duplicates != 0) return 'stored wrong';
      if (s.doneCalls != 1 || s.checkpoint != null) return 'done/checkpoint';
      return s.otherDevice ? 'wrong device' : null;
    });

    await _check(
      'job: connection drop mid page, resume sends no duplicate',
      () async {
        final s = _FakeServer(pageSizes: [650, 650, 650])..dropOnPut = 4;
        try {
          await s.job().run();
          return 'did not pause';
        } on HandOnPaused {
          // expected
        }
        final saved = s.checkpoint;
        if (saved == null || saved.sent != 650) return 'checkpoint $saved';
        await s.job(start: saved).run();
        if (s.duplicates != 0) return '${s.duplicates} duplicates';
        if (s.stored.length != 1950) return 'stored ${s.stored.length}';
        return s.doneCalls == 1 ? null : 'done ${s.doneCalls}';
      },
    );

    await _check('job: stopped, then continued from the saved page', () async {
      final s = _FakeServer(pageSizes: [650, 650, 650])..cancelOnPut = 3;
      final job = s.job();
      s.onCancel = job.cancel;
      try {
        await job.run();
        return 'not stopped';
      } on HandOnCancelled {
        // expected
      }
      if (s.doneCalls != 0) return 'done called after Stop';
      await s.job(start: s.checkpoint).run();
      if (s.duplicates != 0 || s.stored.length != 1950) return 'wrong boxes';
      return s.doneCalls == 1 ? null : 'done ${s.doneCalls}';
    });

    await _check('job: killed app, same boxes never sent twice', () async {
      final s = _FakeServer(pageSizes: [650, 650, 650])..dropOnPut = 5;
      try {
        await s.job().run();
      } on HandOnPaused {
        // the process dies here; only the saved checkpoint survives
      }
      final raw = s.checkpoint?.toJson();
      await s.job(start: HandOnCheckpoint.parse(raw)).run();
      return s.duplicates == 0 && s.stored.length == 1950 ? null : 'duplicates';
    });

    await _check(
      'job: a cursor the server refuses starts over, no repeats',
      () async {
        final s = _FakeServer(pageSizes: [650, 650])..badCursor = true;
        final first = _FakeServer(pageSizes: [650, 650])..dropOnPut = 3;
        try {
          await first.job().run();
        } on HandOnPaused {
          // expected
        }
        s.stored.addAll(first.stored);
        await s.job(start: first.checkpoint).run();
        return s.duplicates == 0 && s.stored.length == 1300 ? null : 'wrong';
      },
    );

    await _check(
      'job: rate limited twice waits 5 s then 10 s, same batch',
      () async {
        final s = _FakeServer(pageSizes: [100])..rateLimitPuts = 2;
        await s.job().run();
        if (s.sleeps.map((d) => d.inSeconds).join(',') != '5,10') {
          return 'sleeps ${s.sleeps.map((d) => d.inSeconds).join(',')}';
        }
        return s.stored.length == 100 && s.duplicates == 0 ? null : 'wrong';
      },
    );

    await _check('job: endless rate limit gives up, no tight loop', () async {
      final s = _FakeServer(pageSizes: [100])..rateLimitPuts = 1 << 30;
      try {
        await s.job().run();
        return 'did not stop';
      } on HandOnFailure catch (f) {
        if (f.kind != HandOnFailureKind.rateLimited) return f.kind.name;
      }
      final total = s.sleeps.fold<Duration>(Duration.zero, (a, b) => a + b);
      if (s.sleeps.length > 20) return '${s.sleeps.length} retries';
      if (s.sleeps.any((d) => d < const Duration(seconds: 5))) {
        return 'short wait';
      }
      return total > const Duration(minutes: 5) ? null : 'waited $total';
    });

    for (final (code, kind) in [
      ('not_waiting', HandOnFailureKind.anotherFinished),
      ('not_found', HandOnFailureKind.deviceGone),
      ('invalid', HandOnFailureKind.rejected),
      ('session_replaced', HandOnFailureKind.sessionEnded),
    ]) {
      await _check('job: put answers $code -> stops as ${kind.name}', () async {
        final s = _FakeServer(pageSizes: [100])..putError = code;
        try {
          await s.job().run();
          return 'did not stop';
        } on HandOnFailure catch (f) {
          if (f.kind != kind) return f.kind.name;
        }
        return s.doneCalls == 0 ? null : 'done after a refusal';
      });
    }

    await _check('job: a dropped line pauses, it is not a failure', () async {
      for (final code in ['timeout', 'disconnected', 'not_connected']) {
        final s = _FakeServer(pageSizes: [100])..putError = code;
        try {
          await s.job().run();
          return '$code finished';
        } on HandOnPaused {
          // expected
        } catch (e) {
          return '$code: ${e.runtimeType}';
        }
      }
      return null;
    });

    await _check('job: Stop wakes a long wait at once', () async {
      final s = _FakeServer(pageSizes: [100])
        ..rateLimitPuts = 1 << 30
        ..isRealSleep = true;
      final job = s.job();
      final run = job.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      job.cancel();
      try {
        await run.timeout(const Duration(seconds: 2));
        return 'not stopped';
      } on HandOnCancelled {
        return null;
      } on TimeoutException {
        return 'slept on';
      }
    });

    await _check('job: an empty history still ends with done', () async {
      final s = _FakeServer(pageSizes: [0]);
      await s.job().run();
      return s.putSizes.isEmpty && s.doneCalls == 1 ? null : 'puts/done';
    });

    await _check('job: counts first, then reports N of M', () async {
      final s = _FakeServer(pageSizes: [650, 650]);
      await s.job().run();
      final last = s.progress.last;
      final first = s.progress.first;
      if (!first.isPreparing) return 'no preparing';
      if (!last.isTotalKnown || last.total != 1300 || last.sent != 1300) {
        return '${last.sent} of ${last.total}';
      }
      return null;
    });

    await _check('job: the target is checked again every 25 pages', () async {
      final s = _FakeServer(pageSizes: List.filled(60, 1));
      await s.job().run();
      return s.verifyCalls == 2 ? null : 'verified ${s.verifyCalls}';
    });
  }

  Future<void> _small() async {
    await _check('checkpoint: round trip, garbage is nothing', () async {
      const c = HandOnCheckpoint(
        cursor: {'c': 3, 'b': 99, 'k': 'dm:a|b'},
        sent: 800,
        skipped: 2,
        already: 5,
      );
      final back = HandOnCheckpoint.parse(c.toJson());
      if (back == null || back.sent != 800 || back.skipped != 2) return 'lost';
      if ((back.cursor as Map)['k'] != 'dm:a|b') return 'cursor changed';
      return HandOnCheckpoint.parse('{nope') == null &&
              HandOnCheckpoint.parse('') == null &&
              HandOnCheckpoint.parse(null) == null
          ? null
          : 'garbage read';
    });
    await _check('device name: plain, cleaned, 60 characters', () async {
      if (handOnDeviceName('Ann\u0000 \u001fphone\n') != 'Ann phone') {
        return 'controls kept';
      }
      if (handOnDeviceName('x' * 90).length != 60) return 'not cut';
      return handOnDeviceName(' \u0007 ') == 'A new device' ? null : 'empty';
    });
    await _check('device id: only 32 hex characters', () async {
      return isDeviceId('1bd6d3cab2c42004583acba1701e9188') &&
              !isDeviceId('1BD6D3CAB2C42004583ACBA1701E9188') &&
              !isDeviceId('short') &&
              !isDeviceId('1bd6d3cab2c42004583acba1701e918g')
          ? null
          : 'accepted a bad id';
    });
  }
}

/// A stand-in server and a stand-in crypto step for the job. A box "exists" for
/// the target once it is stored here, exactly as the real server shows a
/// stored late box to the older device, so a repeated page skips it.
class _FakeServer {
  _FakeServer({required this.pageSizes}) {
    var n = 0;
    pages = [
      for (final size in pageSizes)
        [for (var i = 0; i < size; i++) 'msg-${n++}'],
    ];
  }

  static const target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  static const me = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  final List<int> pageSizes;
  late final List<List<String>> pages;

  final stored = <String>{};
  final putSizes = <int>[];
  final sleeps = <Duration>[];
  final progress = <HandOnProgress>[];
  int duplicates = 0;
  int doneCalls = 0;
  int verifyCalls = 0;
  int puts = 0;
  bool otherDevice = false;
  HandOnCheckpoint? checkpoint;

  int dropOnPut = 0;
  int cancelOnPut = 0;
  int rateLimitPuts = 0;
  String? putError;
  bool badCursor = false;
  bool isRealSleep = false;
  void Function()? onCancel;

  HandOnJob job({HandOnCheckpoint? start}) => HandOnJob(
    targetId: target,
    deviceId: me,
    start: start,
    call: _call,
    rewrap: _rewrap,
    save: (c) async => checkpoint = c,
    scan: (texts) =>
        HandOnScan(candidates: texts.where((t) => !stored.contains(t)).length),
    verifyTarget: () async => verifyCalls++,
    onProgress: progress.add,
    sleep: (d) async {
      sleeps.add(d);
      if (isRealSleep) await Future<void>.delayed(d);
    },
  );

  Future<HandOnPageResult> _rewrap(List<String> texts) async {
    var already = 0;
    final items = <Map<String, String>>[];
    for (final t in texts) {
      if (stored.contains(t)) {
        already++;
      } else {
        items.add({'mid': t, 'iv': '', 'w': '', 'ek': ''});
      }
    }
    return HandOnPageResult(items: items, skipped: 0, already: already);
  }

  Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> args,
  ) async {
    switch (action) {
      case 'e2e.sync.page':
        final cursor = args['cursor'];
        if (badCursor && cursor != null) {
          badCursor = false;
          throw const SocketCallError('invalid');
        }
        final index = cursor is Map ? cursor['c'] as int : 0;
        if (pages.isEmpty) return {'items': [], 'next': null};
        final last = index >= pages.length - 1;
        return {
          'items': [
            for (final t in pages[index]) {'id': 1, 'text': t},
          ],
          'next': last ? null : {'c': index + 1, 'b': 0, 'k': 'dm:x|y'},
        };
      case 'e2e.sync.put':
        puts++;
        if (args['device'] != target) otherDevice = true;
        final err = putError;
        if (err != null) throw SocketCallError(err);
        if (dropOnPut > 0 && puts == dropOnPut) {
          throw const SocketCallError('disconnected');
        }
        if (cancelOnPut > 0 && puts == cancelOnPut) onCancel?.call();
        if (rateLimitPuts > 0) {
          rateLimitPuts--;
          throw const SocketCallError('rate_limited');
        }
        final items = (args['items'] as List).cast<Map<String, String>>();
        putSizes.add(items.length);
        for (final i in items) {
          if (!stored.add(i['mid']!)) duplicates++;
        }
        return {'stored': items.length};
      case 'e2e.sync.done':
        if (args['device'] != target) otherDevice = true;
        doneCalls++;
        return {'done': true};
    }
    throw SocketCallError('unexpected $action');
  }
}

/// A measure of one page of cryptography on the main isolate and on a worker:
/// time, and the longest stretch the main isolate did not answer its timer.
class HandOnBenchmark {
  HandOnBenchmark._();

  static const messages = 400;

  static Future<String> run() async {
    final crypto = E2eCrypto();
    final older = await crypto.generateDeviceKeys();
    final waiting = await crypto.generateDeviceKeys();
    final sender = await crypto.generateDeviceKeys();
    final texts = <String>[];
    for (var i = 0; i < messages; i++) {
      texts.add(
        await crypto.buildEnvelope(
          user: 'bench',
          keys: sender,
          conv: 'dm:bench|bench2',
          recipients: [older.asPublic, sender.asPublic],
          text: 'benchmark message $i',
        ),
      );
    }
    final work = HandOnWork(
      ecdhPkcs8: await older.ecdhPrivate.exportPkcs8Key(),
      deviceId: older.id,
      targetId: waiting.id,
      targetEcdh: waiting.ecdhPub,
      texts: texts,
    );
    final main = await _measure(() => handOnRewrapPage(work));
    final worker = await _measure(() => handOnRewrapInIsolate(work));
    String line(String name, _Measure m) =>
        '$name: ${m.total.inMilliseconds} ms for $messages messages '
        '(${(m.total.inMicroseconds / messages / 1000).toStringAsFixed(2)} ms each), '
        'main isolate stalled up to ${m.longestStall.inMilliseconds} ms, '
        '${m.stalls} stalls over 16 ms';
    return '${line('Main isolate', main)}\n${line('Worker isolate', worker)}';
  }

  static Future<_Measure> _measure(
    Future<HandOnPageResult> Function() body,
  ) async {
    final clock = Stopwatch()..start();
    var last = clock.elapsed;
    var longest = Duration.zero;
    var stalls = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 4), (_) {
      final now = clock.elapsed;
      final gap = now - last;
      last = now;
      if (gap > longest) longest = gap;
      if (gap > const Duration(milliseconds: 16)) stalls++;
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final start = clock.elapsed;
    final result = await body();
    final total = clock.elapsed - start;
    timer.cancel();
    if (result.items.length != messages) throw StateError('wrong count');
    return _Measure(total, longest, stalls);
  }
}

class _Measure {
  const _Measure(this.total, this.longestStall, this.stalls);

  final Duration total;
  final Duration longestStall;
  final int stalls;
}
