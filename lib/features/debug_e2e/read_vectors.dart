import '../../core/utils/mention_text.dart';
import '../../data/e2e/e2e_crypto.dart';
import '../../data/e2e/e2e_models.dart';
import '../../data/e2e/e2e_texts.dart';
import '../../data/repositories/e2e_repository.dart';

/// The self-test of the read side: key pins on read, the placeholder for each
/// failure code, and @tags in decrypted text. No server and no storage: the
/// repository is given the sender's device and an in-memory pin map.
class ReadVectors {
  ReadVectors(this._check, this._e2e);

  final Future<void> Function(String name, Future<String?> Function() body)
  _check;
  final E2eRepository _e2e;
  final _crypto = E2eCrypto();

  Future<void> run() async {
    await _pins();
    await _placeholders();
    await _mentions();
  }

  // ---- pins on read ---------------------------------------------------------

  Future<void> _pins() async {
    final sender = await _crypto.generateDeviceKeys();
    final reader = await _crypto.generateDeviceKeys();
    final other = await _crypto.generateDeviceKeys();
    const text = 'Pin test ✓';
    final conv = E2eCrypto.dmLabel('pin-a', 'pin-b');
    final env = await _crypto.buildEnvelope(
      user: 'pin-a',
      keys: sender,
      conv: conv,
      recipients: [sender.asPublic, reader.asPublic],
      text: text,
    );
    Future<E2eReading> open(
      Map<String, ({String ecdh, String sign})> pins, {
      E2eDevicePublic? served,
    }) => _e2e.open(
      text: env,
      convId: 'dm:pin-b',
      expectConv: conv,
      keys: reader,
      testPins: pins,
      deviceFor: (user, id) async => user == 'pin-a' && id == sender.id
          ? (served ?? sender.asPublic)
          : null,
    );

    await _check('pins: a matching pin opens the message', () async {
      final pins = {sender.id: (ecdh: sender.ecdhPub, sign: sender.signPub)};
      final r = await open(pins);
      return r.state == E2eReadState.ok && r.text == text
          ? null
          : 'not opened (${r.code})';
    });
    await _check(
      'pins: a first-seen sender device is pinned, then opens',
      () async {
        final pins = <String, ({String ecdh, String sign})>{};
        final r = await open(pins);
        if (r.state != E2eReadState.ok) return 'not opened (${r.code})';
        return pins[sender.id]?.sign == sender.signPub ? null : 'not pinned';
      },
    );
    await _check('pins: a changed sender key is refused, no text', () async {
      final pins = {sender.id: (ecdh: other.ecdhPub, sign: other.signPub)};
      final r = await open(pins);
      if (r.state != E2eReadState.cantDecrypt) return 'state ${r.state}';
      if (r.code != 'key_changed') return 'code ${r.code}';
      return r.text == null ? null : 'text was returned';
    });
    await _check('pins: a changed ecdh key alone is refused', () async {
      final pins = {sender.id: (ecdh: other.ecdhPub, sign: sender.signPub)};
      final r = await open(pins);
      return r.code == 'key_changed' ? null : 'code ${r.code}';
    });
    await _check('pins: a refusal leaves the pin as it was', () async {
      final pins = {sender.id: (ecdh: other.ecdhPub, sign: other.signPub)};
      await open(pins);
      return pins[sender.id]?.sign == other.signPub &&
              pins[sender.id]?.ecdh == other.ecdhPub
          ? null
          : 'pin was rewritten';
    });
    await _check('pins: the server serving another key is refused', () async {
      final pins = {sender.id: (ecdh: sender.ecdhPub, sign: sender.signPub)};
      final swapped = E2eDevicePublic(
        id: sender.id,
        ecdh: sender.ecdhPub,
        sign: other.signPub,
      );
      final r = await open(pins, served: swapped);
      return r.code == 'key_changed' ? null : 'code ${r.code}';
    });
    await _check(
      'pins: the same message opens once the new key is trusted',
      () async {
        final pins = {sender.id: (ecdh: other.ecdhPub, sign: other.signPub)};
        final refused = await open(pins);
        if (refused.code != 'key_changed') return 'not refused first';
        pins[sender.id] = (ecdh: sender.ecdhPub, sign: sender.signPub);
        final r = await open(pins);
        return r.state == E2eReadState.ok && r.text == text
            ? null
            : 'not opened';
      },
    );
  }

  // ---- placeholders ---------------------------------------------------------

  static const _web = {
    'key_changed':
        "🔒 This sender's security key changed. Check the safety number before trusting new messages.",
    'bad_signature': '🔒 This message could not be verified and was hidden.',
    'decrypt_failed': '🔒 This message is damaged and could not be opened.',
    'wrong_conversation':
        '🔒 This message does not belong to this conversation and was hidden.',
    'bad_payload': '🔒 This message could not be read.',
  };

  Future<void> _placeholders() async {
    await _check(
      'placeholders: five texts are the web\'s, word for word',
      () async {
        for (final e in _web.entries) {
          if (E2eTexts.unreadableFor(e.key) != e.value) {
            return 'differs: ${e.key}';
          }
        }
        return null;
      },
    );
    await _check('placeholders: three are worded for a phone', () async {
      const codes = [
        'not_for_this_device',
        'no_device',
        'unknown_sender_device',
      ];
      for (final c in codes) {
        final t = E2eTexts.unreadableFor(c);
        if (t == E2eTexts.unreadable) return 'generic: $c';
        if (t.contains('browser') || t.contains('page')) {
          return 'web wording: $c';
        }
      }
      final before = E2eTexts.unreadableFor('not_for_this_device');
      if (!before.contains(
        'Approve this device on another device you already use',
      )) {
        return 'approve advice lost';
      }
      return null;
    });
    await _check('placeholders: every code has its own text', () async {
      final texts = {
        for (final c in E2eTexts.unreadableCodes) E2eTexts.unreadableFor(c),
      };
      if (E2eTexts.unreadableCodes.length != 8) return 'expected 8 codes';
      return texts.length == 8 && !texts.contains(E2eTexts.unreadable)
          ? null
          : 'two codes share a text';
    });
    await _check(
      'placeholders: other codes and none get the generic line',
      () async {
        return E2eTexts.unreadableFor('directory_limit') ==
                    E2eTexts.unreadable &&
                E2eTexts.unreadableFor(null) == E2eTexts.unreadable &&
                E2eTexts.unreadable ==
                    "🔒 This message can't be read on this device."
            ? null
            : 'wrong fallback';
      },
    );
    await _check(
      'placeholders: codes the reader raises map to their text',
      () async {
        final sender = await _crypto.generateDeviceKeys();
        final reader = await _crypto.generateDeviceKeys();
        final stranger = await _crypto.generateDeviceKeys();
        final conv = E2eCrypto.dmLabel('ph-a', 'ph-b');
        final env = await _crypto.buildEnvelope(
          user: 'ph-a',
          keys: sender,
          conv: conv,
          recipients: [sender.asPublic, reader.asPublic],
          text: 'x',
        );
        Future<String?> signKey(String u, String d) async =>
            u == 'ph-a' && d == sender.id ? sender.signPub : null;
        Future<E2eReading> open({
          E2eDeviceKeys? keys,
          String? expect,
          Future<String?> Function(String, String)? key,
        }) => _e2e.open(
          text: env,
          convId: 'dm:ph-b',
          expectConv: expect ?? conv,
          keys: keys ?? reader,
          signKeyFor: key ?? signKey,
        );
        final cases = <String, E2eReading>{
          'not_for_this_device': await open(keys: stranger),
          'wrong_conversation': await open(expect: 'dm:ph-a|ph-c'),
          'unknown_sender_device': await open(key: (_, _) async => null),
          'bad_signature': await open(key: (_, _) async => stranger.signPub),
        };
        for (final e in cases.entries) {
          if (e.value.code != e.key) return '${e.key} raised ${e.value.code}';
          if (E2eTexts.unreadableFor(e.value.code) == E2eTexts.unreadable) {
            return '${e.key} shows the generic line';
          }
        }
        return null;
      },
    );
    await _check('texts: new device and key changed notices', () async {
      final a = E2eTexts.newDeviceNotice('ann', ['Pixel 8', 'Mac']);
      final b = E2eTexts.newDeviceNotice('ann', []);
      return a.startsWith(
                '@ann added a new device (Pixel 8, Mac). Messages you send them now are encrypted for it too.',
              ) &&
              b.startsWith('@ann added a new device. Messages') &&
              E2eTexts.keyChangedNotice('ann') ==
                  "@ann's security key changed. Open the lock in the chat header and check the safety number."
          ? null
          : 'wording differs';
    });
    await _check('texts: approve, recovery codes', () async {
      return E2eTexts.approveTitle('Pixel') ==
                  'Show your earlier messages on Pixel?' &&
              E2eTexts.notMe == 'That is not me' &&
              E2eTexts.allSetBody('Pixel') ==
                  'Your earlier messages are now on Pixel.' &&
              E2eTexts.badCode.startsWith(
                'A recovery code has 26 letters and numbers',
              ) &&
              E2eTexts.wrongCode ==
                  'That code does not open the recovery key. Check it and try again.'
          ? null
          : 'wording differs';
    });
  }

  // ---- @tags in decrypted text ------------------------------------------------

  Future<void> _mentions() async {
    List<String> users(String t) => [
      for (final r in MentionText.split(t))
        if (r.user != null) r.user!,
    ];
    await _check('mentions: the web rule on plain strings', () async {
      final ok =
          users('hi @Anna and (@bob)!').join(',') == 'anna,bob' &&
          users('mail me@x.com').isEmpty &&
          users('@a').isEmpty &&
          users('@anna.').join(',') == 'anna' &&
          users('ok,@dev_1 x').join(',') == 'dev_1' &&
          users('a@@bob').isEmpty;
      final rebuilt = MentionText.split('x @ann y').map((r) => r.text).join();
      return ok && rebuilt == 'x @ann y' ? null : 'rule differs';
    });
    await _check('mentions: found in decrypted group text', () async {
      final sender = await _crypto.generateDeviceKeys();
      final reader = await _crypto.generateDeviceKeys();
      final conv = E2eCrypto.groupLabel('design');
      const text = 'Please review @Priya and @outsider, thanks @me-user';
      final env = await _crypto.buildEnvelope(
        user: 'grp-a',
        keys: sender,
        conv: conv,
        recipients: [sender.asPublic, reader.asPublic],
        text: text,
      );
      final r = await _e2e.open(
        text: env,
        convId: 'group:design',
        expectConv: conv,
        keys: reader,
        signKeyFor: (u, d) async => d == sender.id ? sender.signPub : null,
      );
      if (r.state != E2eReadState.ok) return 'not opened';
      final found = users(r.text!);
      if (found.join(',') != 'priya,outsider,me-user') return 'found $found';
      final members = {'priya', 'me-user'};
      final drawn = found.where(members.contains).join(',');
      return drawn == 'priya,me-user' ? null : 'drawn $drawn';
    });
    await _check('mentions: an envelope shown as text has no tag', () async {
      return users('e2e1:{"from":"x"}').isEmpty ? null : 'tag in envelope';
    });
  }
}
