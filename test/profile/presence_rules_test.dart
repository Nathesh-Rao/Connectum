import 'package:connectum/data/profile/presence.dart';
import 'package:flutter_test/flutter_test.dart';

import 'profile_fakes.dart';

void main() {
  group('derive (display only)', () {
    const cases = {
      '': Presence.available,
      '   ': Presence.available,
      'In the office until 5': Presence.available,
      'Do not disturb': Presence.dnd,
      'please DO NOT DISTURB me': Presence.dnd,
      'dnd': Presence.dnd,
      ' DND ': Presence.dnd,
      'dnd until 5': Presence.available,
      'In a meeting': Presence.meeting,
      'meeting with the board': Presence.meeting,
      'Busy': Presence.busy,
      'busy today': Presence.busy,
      'Away': Presence.away,
      'gone offline': Presence.away,
      'Offline': Presence.away,
    };
    cases.forEach((text, want) {
      test('"$text" reads as ${want.wire}', () {
        expect(Presence.derive(text), want);
      });
    });

    test('do not disturb wins over meeting, busy and away', () {
      expect(Presence.derive('do not disturb, in a meeting'), Presence.dnd);
      expect(Presence.derive('meeting, busy'), Presence.meeting);
      expect(Presence.derive('busy, away'), Presence.busy);
    });

    test('null status is available', () {
      expect(Presence.derive(null), Presence.available);
    });
  });

  group('parse', () {
    test('only the five exact words', () {
      for (final p in Presence.values) {
        expect(Presence.parse(p.wire), p);
      }
      expect(Presence.parse('Busy'), isNull);
      expect(Presence.parse('online'), isNull);
      expect(Presence.parse(''), isNull);
      expect(Presence.parse(null), isNull);
      expect(Presence.parse(3), isNull);
    });

    test('the labels', () {
      expect(Presence.values.map((p) => p.label), [
        'Available',
        'Busy',
        'In a meeting',
        'Away',
        'Do not disturb',
      ]);
    });
  });

  group('profile events', () {
    test('the chosen presence wins over the status text', () {
      final rig = ProfileRig();
      rig.profiles.onEvent(
        profileEvent('bob', status: 'In a meeting', presence: 'busy'),
      );
      expect(rig.profiles.presenceOf('bob'), Presence.busy);
      expect(rig.profiles.chosenOf('bob'), Presence.busy);
    });

    test('a null presence is derived for display and stays null', () {
      final rig = ProfileRig();
      rig.profiles.onEvent(
        profileEvent('bob', status: 'In a meeting', presence: null),
      );
      expect(rig.profiles.chosenOf('bob'), isNull);
      expect(rig.profiles.presenceOf('bob'), Presence.meeting);
    });

    test('an unknown word counts as never chosen', () {
      final rig = ProfileRig();
      rig.profiles.onEvent(profileEvent('bob', presence: 'online'));
      expect(rig.profiles.chosenOf('bob'), isNull);
      expect(rig.profiles.presenceOf('bob'), Presence.available);
    });

    test('names are case-blind', () {
      final rig = ProfileRig();
      rig.profiles.onEvent(profileEvent('Bob', presence: 'away'));
      expect(rig.profiles.presenceOf('bOB'), Presence.away);
    });

    test('a null status clears it (another device)', () {
      final rig = ProfileRig();
      rig.ownProfile(status: 'Out today', presence: 'away');
      expect(rig.profiles.statusOf('me'), 'Out today');
      rig.ownProfile(status: null, presence: 'away');
      expect(rig.profiles.statusOf('me'), isNull);
      expect(rig.profiles.presenceOf('me'), Presence.away);
    });

    test('a profile event from another device updates this one', () {
      final rig = ProfileRig();
      rig.ownProfile(status: 'a', presence: 'busy');
      rig.ownProfile(status: 'a', presence: 'dnd');
      expect(rig.profiles.presenceOf('me'), Presence.dnd);
    });

    test('my own event without a presence key keeps mine', () {
      final rig = ProfileRig();
      rig.ownProfile(status: 'a', presence: 'busy');
      rig.profiles.onEvent({'type': 'profile', 'user': 'me', 'status': 'b'});
      expect(rig.profiles.chosenOf('me'), Presence.busy);
      expect(rig.profiles.statusOf('me'), 'b');
    });

    test("another person's event without a presence key says never chosen", () {
      final rig = ProfileRig();
      rig.profiles.onEvent(profileEvent('bob', presence: 'busy'));
      rig.profiles.onEvent({'type': 'profile', 'user': 'bob', 'status': null});
      expect(rig.profiles.chosenOf('bob'), isNull);
    });

    test('a blank status is none; other event types are ignored', () {
      final rig = ProfileRig();
      rig.profiles.onEvent(profileEvent('bob', status: '   '));
      expect(rig.profiles.statusOf('bob'), isNull);
      rig.profiles.onEvent({'type': 'users', 'user': 'bob'});
      expect(rig.profiles.profiles.length, 1);
    });
  });
}
