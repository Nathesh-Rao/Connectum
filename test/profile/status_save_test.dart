import 'package:connectum/data/profile/presence.dart';
import 'package:connectum/data/repositories/profile_repository.dart';
import 'package:connectum/features/profile/profile_texts.dart';
import 'package:connectum/features/profile_status/profile_status_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'profile_fakes.dart';

ProfileStatusController _editor(ProfileRig rig) => ProfileStatusController(
  repository: rig.repository,
  profiles: rig.profiles,
  avatars: rig.avatars,
  store: rig.session,
)..onInit();

Map<String, dynamic> _refuse(String line, String code) => {
  'type': 'error',
  'cmd': line.substring(1).split(' ').first,
  'code': code,
  'text': 'server words',
};

void main() {
  group('repository commands', () {
    test('setStatus sends the trimmed text and waits for the ack', () async {
      final rig = ProfileRig();
      await rig.repository.setStatus('  In the office  ');
      expect(rig.socket.sent, ['/setstatus In the office']);
    });

    test('an empty status sends a bare /setstatus', () async {
      final rig = ProfileRig();
      await rig.repository.setStatus('   ');
      expect(rig.socket.sent, ['/setstatus']);
    });

    test('a status that starts with a slash goes out as it is', () async {
      final rig = ProfileRig();
      await rig.repository.setStatus('/away');
      expect(rig.socket.sent, ['/setstatus /away']);
    });

    test('setPresence sends the wire word', () async {
      final rig = ProfileRig();
      await rig.repository.setPresence(Presence.meeting);
      expect(rig.socket.sent, ['/setpresence meeting']);
    });

    test('the server refusals carry their code', () async {
      final rig = ProfileRig();
      for (final code in ['invalid_status', 'rate_limited']) {
        rig.socket.onCommand = (l) => _refuse(l, code);
        await expectLater(
          rig.repository.setStatus('x'),
          throwsA(
            isA<ProfileCommandException>().having((e) => e.code, 'code', code),
          ),
        );
      }
      rig.socket.onCommand = (l) => _refuse(l, 'invalid_presence');
      await expectLater(
        rig.repository.setPresence(Presence.busy),
        throwsA(
          isA<ProfileCommandException>().having(
            (e) => e.code,
            'code',
            'invalid_presence',
          ),
        ),
      );
    });

    test('an answer for another command is not ours', () async {
      final rig = ProfileRig();
      rig.socket.onCommand = (l) => {
        'type': 'ack',
        'cmd': 'setavatar',
        'ok': true,
      };
      await expectLater(
        rig.repository.setStatus('x'),
        throwsA(
          isA<ProfileCommandException>().having(
            (e) => e.code,
            'code',
            'timeout',
          ),
        ),
      );
    });

    test('offline sends nothing and says so', () async {
      final rig = ProfileRig()..socket.online = false;
      await expectLater(
        rig.repository.setStatus('x'),
        throwsA(
          isA<ProfileCommandException>().having(
            (e) => e.code,
            'code',
            'offline',
          ),
        ),
      );
      expect(rig.socket.sent, isEmpty);
    });
  });

  group('the editor sends only what changed, status first', () {
    test('presence only', () async {
      final rig = ProfileRig()
        ..ownProfile(status: 'hello', presence: 'available');
      final c = _editor(rig)..choose(Presence.busy);
      expect(await c.save(), isTrue);
      expect(rig.socket.sent, ['/setpresence busy']);
    });

    test('status only', () async {
      final rig = ProfileRig()..ownProfile(status: null, presence: 'busy');
      final c = _editor(rig)..text.text = 'Back at 3';
      expect(await c.save(), isTrue);
      expect(rig.socket.sent, ['/setstatus Back at 3']);
    });

    test('both: /setstatus first, then /setpresence', () async {
      final rig = ProfileRig()
        ..ownProfile(status: 'old', presence: 'available');
      final c = _editor(rig)
        ..text.text = 'new'
        ..choose(Presence.dnd);
      expect(await c.save(), isTrue);
      expect(rig.socket.sent, ['/setstatus new', '/setpresence dnd']);
    });

    test('nothing changed sends nothing', () async {
      final rig = ProfileRig()..ownProfile(status: 'same', presence: 'away');
      final c = _editor(rig);
      expect(c.hasChanges, isFalse);
      expect(await c.save(), isTrue);
      expect(rig.socket.sent, isEmpty);
    });

    test('clearing the message sends a bare /setstatus', () async {
      final rig = ProfileRig()..ownProfile(status: 'bye', presence: 'away');
      final c = _editor(rig)..clear();
      expect(await c.save(), isTrue);
      expect(rig.socket.sent, ['/setstatus']);
    });

    test(
      'never chosen: the derived presence is shown and never sent back',
      () async {
        final rig = ProfileRig()
          ..ownProfile(status: 'In a meeting', presence: null);
        final c = _editor(rig);
        expect(c.presence.value, Presence.meeting);
        expect(await c.save(), isTrue);
        expect(rig.socket.sent, isEmpty);
      },
    );

    test('picking the derived presence again sends no presence', () async {
      final rig = ProfileRig()..ownProfile(status: 'Busy', presence: null);
      final c = _editor(rig)
        ..choose(Presence.busy)
        ..text.text = 'Busy until noon';
      expect(await c.save(), isTrue);
      expect(rig.socket.sent, ['/setstatus Busy until noon']);
    });

    test(
      'picking a different presence than the derived one sends it',
      () async {
        final rig = ProfileRig()..ownProfile(status: 'Busy', presence: null);
        final c = _editor(rig)..choose(Presence.away);
        await c.save();
        expect(rig.socket.sent, ['/setpresence away']);
      },
    );

    test('the text is cleaned and cut before it is sent', () async {
      final rig = ProfileRig()..ownProfile();
      final c = _editor(rig)..text.text = '  hi\nthere ';
      await c.save();
      expect(rig.socket.sent, ['/setstatus hithere']);
    });
  });

  group('failures keep the draft', () {
    test('offline: says so, sends nothing, keeps the draft', () async {
      final rig = ProfileRig()..ownProfile();
      rig.socket.online = false;
      final c = _editor(rig)..text.text = 'draft';
      expect(await c.save(), isFalse);
      expect(c.error.value, ProfileTexts.offline);
      expect(c.text.text, 'draft');
      expect(c.isDirty.value, isTrue);
      expect(rig.socket.sent, isEmpty);
    });

    test(
      'invalid_status: message shown, draft kept, presence not sent',
      () async {
        final rig = ProfileRig()..ownProfile();
        rig.socket.onCommand = (l) => _refuse(l, 'invalid_status');
        final c = _editor(rig)
          ..text.text = 'x'
          ..choose(Presence.busy);
        expect(await c.save(), isFalse);
        expect(c.error.value, ProfileTexts.commandError('invalid_status'));
        expect(c.error.value, contains('140'));
        expect(c.text.text, 'x');
        expect(rig.socket.sent, ['/setstatus x']);
      },
    );

    test(
      'rate_limited on the presence: retry sends only the presence',
      () async {
        final rig = ProfileRig()
          ..ownProfile(status: null, presence: 'available');
        rig.socket.onCommand = (l) => l.startsWith('/setpresence')
            ? _refuse(l, 'rate_limited')
            : {'type': 'ack', 'cmd': 'setstatus', 'ok': true};
        final c = _editor(rig)
          ..text.text = 'hello'
          ..choose(Presence.away);
        expect(await c.save(), isFalse);
        expect(c.error.value, ProfileTexts.commandError('rate_limited'));
        expect(c.isDirty.value, isTrue);

        rig.socket.sent.clear();
        rig.socket.onCommand = (l) => {
          'type': 'ack',
          'cmd': 'setpresence',
          'ok': true,
        };
        expect(await c.save(), isTrue);
        expect(rig.socket.sent, ['/setpresence away']);
        expect(c.isDirty.value, isFalse);
      },
    );

    test('invalid_presence has its own message', () {
      expect(
        ProfileTexts.commandError('invalid_presence'),
        isNot(ProfileTexts.commandError('invalid_status')),
      );
      expect(ProfileTexts.commandError('rate_limited'), contains('Wait'));
    });

    test('no answer: a timeout message and the draft stays', () async {
      final rig = ProfileRig()..ownProfile();
      rig.socket.onCommand = (l) => null;
      final c = _editor(rig)..text.text = 'x';
      expect(await c.save(), isFalse);
      expect(c.error.value, ProfileTexts.timeout);
      expect(c.isSaving.value, isFalse);
    });
  });
}
