import 'package:connectum/features/conversation/models/mention_picker.dart';
import 'package:flutter_test/flutter_test.dart';

MentionPerson p(String user, [String name = '']) =>
    MentionPerson(username: user, name: name);

List<String> names(List<MentionPerson> l) => [for (final x in l) x.username];

void main() {
  group('detect', () {
    test('opens at start, after space, line break and brackets', () {
      expect(MentionPicker.detect('@a', 2)?.query, 'a');
      expect(MentionPicker.detect('hi @a', 5)?.query, 'a');
      expect(MentionPicker.detect('hi\n@a', 5)?.query, 'a');
      for (final o in ['(', '[', '{', '"', "'"]) {
        expect(MentionPicker.detect('x $o@a', 5)?.query, 'a', reason: o);
      }
    });
    test('an empty query opens', () {
      expect(MentionPicker.detect('hi @', 4)?.query, '');
    });
    test('inside a word does nothing', () {
      expect(MentionPicker.detect('a@', 2), isNull);
      expect(MentionPicker.detect('a@b', 3), isNull);
    });
    test('a space closes it, the caret decides, not the end', () {
      expect(MentionPicker.detect('@ann x', 6), isNull);
      final q = MentionPicker.detect('@an and more', 3);
      expect(q?.query, 'an');
      expect(q?.start, 0);
    });
    test('at most 24 characters after the @', () {
      expect(MentionPicker.detect('@${'a' * 24}', 25)?.query, 'a' * 24);
      expect(MentionPicker.detect('@${'a' * 25}', 26), isNull);
    });
  });

  group('filter', () {
    final people = [
      p('zoe', 'Zoe Hall'),
      p('maria', 'Anna Maria'),
      p('anne', 'Zed Anne'),
      p('ann', 'Ann Rao'),
      p('banna', 'Banna'),
      p('me', 'Me Myself'),
    ];
    test('nothing typed: everyone but me, by name', () {
      expect(names(MentionPicker.filter(people, '', me: 'me')), [
        'ann',
        'maria',
        'banna',
        'anne',
        'zoe',
      ]);
    });
    test('rank 0 prefix, rank 1 word start, rank 2 contains', () {
      // maria: whole name "anna maria" starts with it (rank 0, by name).
      expect(names(MentionPicker.filter(people, 'ann', me: 'me')), [
        'ann',
        'maria',
        'anne',
        'banna',
      ]);
      // A word of the name starts with it (rank 1) before one that contains it.
      final out = MentionPicker.filter(
        [p('xx', 'Bo Nanna'), p('yy', 'Carl Banana'), p('zz', 'Nan')],
        'nan',
        me: 'me',
      );
      expect(names(out), ['zz', 'xx', 'yy']);
    });
    test('case-insensitive, no match gives nothing', () {
      expect(names(MentionPicker.filter(people, 'ZOE', me: 'me')), ['zoe']);
      expect(MentionPicker.filter(people, 'qq', me: 'me'), isEmpty);
    });
    test('myself is never listed, each person once, at most 6', () {
      expect(MentionPicker.filter(people, 'myself', me: 'me'), isEmpty);
      expect(names(MentionPicker.filter(people, 'mar', me: 'me')), ['maria']);
      final many = [for (var i = 0; i < 10; i++) p('user$i'), p('user1')];
      final out = MentionPicker.filter(many, '', me: 'x');
      expect(out.length, 6);
      expect(names(out).toSet().length, 6);
    });
  });

  group('insert', () {
    test('adds the username and a space', () {
      const text = 'hi @an';
      final at = MentionPicker.detect(text, 6)!;
      final r = MentionPicker.insert(text, at, 6, 'Ann');
      expect(r.text, 'hi @ann ');
      expect(r.caret, 8);
    });
    test('no extra space when one follows; caret in the middle', () {
      const text = 'hi @an and more';
      final at = MentionPicker.detect(text, 6)!;
      final r = MentionPicker.insert(text, at, 6, 'ann');
      expect(r.text, 'hi @ann and more');
      expect(r.caret, 8);
    });
    test('text after the caret without a space gets one', () {
      const text = '@anx';
      final at = MentionPicker.detect(text, 3)!;
      final r = MentionPicker.insert(text, at, 3, 'ann');
      expect(r.text, '@ann x');
      expect(r.caret, 5);
    });
  });
}
