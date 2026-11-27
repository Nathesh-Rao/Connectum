import 'package:connectum/core/utils/transform_formatter.dart';
import 'package:connectum/data/profile/personal_details.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/features/profile/profile_texts.dart';
import 'package:connectum/features/profile_details/profile_details_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'profile_fakes.dart';

const _record = {
  'profile': {
    'address': '12 Old Street',
    'gender': 'male',
    'dob': '2000-01-02',
    'education': 'MBA',
    'skills': ['Erlang', 'Sales'],
    'roles': ['admin'],
  },
};

Future<(ProfileDetailsController, ProfileRig)> _open([
  Map<String, dynamic> answer = _record,
]) async {
  final rig = ProfileRig();
  rig.socket.onSd = (action, args) async => action == 'profile.get'
      ? answer
      : {
          'profile': {...args},
        };
  final c = ProfileDetailsController(repository: rig.repository)..onInit();
  await Future<void>.delayed(Duration.zero);
  return (c, rig);
}

String _typed(String text, int limit) => TransformFormatter(
  (t) => DetailsRules.typed(t, limit),
).formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text)).text;

void main() {
  group('byte limits', () {
    test('address allows 200 bytes: plain text counts one per character', () {
      expect(_typed('a' * 200, 200), 'a' * 200);
      expect(_typed('a' * 201, 200), 'a' * 200);
    });

    test('2-byte characters: 101 are cut to 100', () {
      final cut = _typed('é' * 101, DetailsRules.addressBytes);
      expect(cut, 'é' * 100);
      expect(DetailsRules.bytes(cut), 200);
    });

    test('3-byte characters never end half way', () {
      final cut = _typed('अ' * 100, DetailsRules.addressBytes);
      expect(cut, 'अ' * 66);
      expect(DetailsRules.bytes(cut), 198);
    });

    test('4-byte emoji: 51 are cut to 50', () {
      final cut = _typed('😀' * 51, DetailsRules.addressBytes);
      expect(cut, '😀' * 50);
    });

    test('education allows 120 bytes, the server limit, not the web 150', () {
      expect(_typed('a' * 150, DetailsRules.educationBytes), 'a' * 120);
      expect(_typed('é' * 70, DetailsRules.educationBytes), 'é' * 60);
    });

    test('control characters are removed', () {
      expect(_typed('a\nb\u0000c', 200), 'abc');
    });

    test('bytes counts UTF-8', () {
      expect(DetailsRules.bytes('aé😀'), 1 + 2 + 4);
    });
  });

  group('skills', () {
    test('trimmed, blanks dropped, duplicates ignored case-blind', () {
      expect(
        DetailsRules.parseSkills(' React, ,erlang,REACT , Erlang,UI/UX,'),
        ['React', 'erlang', 'UI/UX'],
      );
    });

    test('at most 30', () {
      final ok = [for (var i = 0; i < 30; i++) 's$i'];
      final over = [...ok, 'one more'];
      expect(DetailsRules.skillsError(ok), isNull);
      expect(DetailsRules.skillsError(over), 'At most 30 skills.');
    });

    test('each skill is 40 bytes at most, counted in bytes', () {
      expect(DetailsRules.skillsError(['a' * 40]), isNull);
      expect(
        DetailsRules.skillsError(['a' * 41]),
        'Each skill must be 40 characters or fewer.',
      );
      expect(DetailsRules.skillsError(['é' * 21]), isNotNull);
    });
  });

  group('dates', () {
    test('wire format YYYY-MM-DD', () {
      expect(DetailsRules.dobToWire(DateTime(2001, 4, 3)), '2001-04-03');
      expect(DetailsRules.dobFromWire('2001-04-03'), DateTime(2001, 4, 3));
      expect(DetailsRules.dobFromWire('2001-02-30'), isNull);
      expect(DetailsRules.dobFromWire('nope'), isNull);
    });

    test('the earliest date is 1900', () {
      expect(DetailsRules.earliestBirth, DateTime(1900));
    });
  });

  group('loading and saving', () {
    test('profile.get fills the form', () async {
      final (c, rig) = await _open();
      expect(rig.socket.sdCalls.first.action, 'profile.get');
      expect(c.state.value, AppViewState.content);
      expect(c.gender.value, 'male');
      expect(c.dob.value, '2000-01-02');
      expect(c.address.text, '12 Old Street');
      expect(c.skills.text, 'Erlang, Sales');
      expect(c.skillList, ['Erlang', 'Sales']);
      expect(c.isDirty.value, isFalse);
    });

    test('a failed load shows an error with retry', () async {
      final rig = ProfileRig();
      rig.socket.onSd = (a, b) async =>
          throw const SocketCallError('error', 'boom');
      final c = ProfileDetailsController(repository: rig.repository)..onInit();
      await Future<void>.delayed(Duration.zero);
      expect(c.state.value, AppViewState.error);
      expect(c.errorMessage.value, 'boom');
    });

    test(
      'clearing every field sends null for each, never omits the key',
      () async {
        final (c, rig) = await _open();
        c.address.clear();
        c.skills.clear();
        c.selectGender('male');
        c.setDob(null);
        expect(c.isDirty.value, isTrue);
        expect(await c.save(), isTrue);
        final update = rig.socket.sdCalls.last;
        expect(update.action, 'profile.update');
        expect(update.args, {
          'address': null,
          'skills': null,
          'gender': null,
          'dob': null,
        });
        expect(update.args.containsKey('address'), isTrue);
      },
    );

    test('only what changed is sent', () async {
      final (c, rig) = await _open();
      c.education.text = 'MBA, B.Tech';
      await c.save();
      expect(rig.socket.sdCalls.last.args, {'education': 'MBA, B.Tech'});
    });

    test('skills go as a list; gender and dob as wire values', () async {
      final (c, rig) = await _open();
      c.skills.text = 'Erlang, Dart, erlang';
      c.selectGender('prefer_not_to_say');
      c.setDob(DateTime(1999, 12, 31));
      await c.save();
      expect(rig.socket.sdCalls.last.args, {
        'skills': ['Erlang', 'Dart'],
        'gender': 'prefer_not_to_say',
        'dob': '1999-12-31',
      });
    });

    test('nothing changed makes no call', () async {
      final (c, rig) = await _open();
      expect(await c.save(), isTrue);
      expect(rig.socket.sdCalls.length, 1);
    });

    test('a refusal shows the server message and keeps the draft', () async {
      final (c, rig) = await _open();
      rig.socket.onSd = (a, b) async => throw const SocketCallError(
        'invalid',
        'education is too long (max 120).',
      );
      c.education.text = 'changed';
      expect(await c.save(), isFalse);
      expect(c.error.value, 'education is too long (max 120).');
      expect(c.education.text, 'changed');
      expect(c.isDirty.value, isTrue);
      expect(c.isSaving.value, isFalse);
    });

    test('no connection says so, and keeps the draft', () async {
      final (c, rig) = await _open();
      rig.socket.onSd = (a, b) async =>
          throw const SocketCallError('not_connected');
      c.address.text = 'new';
      expect(await c.save(), isFalse);
      expect(c.error.value, ProfileTexts.offline);
      expect(c.address.text, 'new');
    });

    test('too many skills is refused before any call', () async {
      final (c, rig) = await _open();
      c.skills.text = [for (var i = 0; i < 31; i++) 's$i'].join(',');
      expect(await c.save(), isFalse);
      expect(c.error.value, 'At most 30 skills.');
      expect(rig.socket.sdCalls.length, 1);
    });

    test('success: "Personal details saved", form is clean', () async {
      final (c, _) = await _open();
      c.address.text = 'New place';
      expect(await c.save(), isTrue);
      expect(c.isDirty.value, isFalse);
      expect(ProfileTexts.detailsSaved, 'Personal details saved');
    });

    test('the private note', () {
      expect(
        ProfileTexts.detailsPrivate,
        'Personal details are private to you and organization administrators.',
      );
    });
  });
}
