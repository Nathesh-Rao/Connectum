import 'package:connectum/core/utils/mention_text.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> tags(String text) => [
  for (final r in MentionText.split(text))
    if (r.user != null) r.user!,
];

void main() {
  group('MentionText', () {
    test('start of text, after space, after (', () {
      expect(tags('@ann hi'), ['ann']);
      expect(tags('hi @ann'), ['ann']);
      expect(tags('hi (@ann)'), ['ann']);
    });
    test('inside a word or an email is not a tag', () {
      expect(tags('ab@cd'), isEmpty);
      expect(tags('a@b.com'), isEmpty);
      expect(tags('@@ann'), isEmpty);
    });
    test('a trailing . - _ is not part of the name', () {
      expect(tags('@ann.'), ['ann']);
      expect(tags('@ann-'), ['ann']);
      expect(tags('@a_n.n_'), ['a_n.n']);
      expect(MentionText.split('@ann.').first.text, '@ann');
    });
    test('length 2 to 24', () {
      expect(tags('@a'), isEmpty);
      expect(tags('@a.'), isEmpty);
      expect(tags('@ab'), ['ab']);
      expect(tags('@${'a' * 24}'), ['a' * 24]);
      // The tag is the first 24 characters; the 25th is plain text.
      expect(tags('@${'a' * 25}'), ['a' * 24]);
    });
    test('lower case, several tags, joined runs give the text back', () {
      const text = 'Hi @Ann and @BOB, see @zed.';
      expect(tags(text), ['ann', 'bob', 'zed']);
      expect(MentionText.split(text).map((r) => r.text).join(), text);
    });
  });

  group('MentionPeople', () {
    const people = MentionPeople(
      me: 'me',
      names: {'ann': 'Ann Rao', 'bob': ' '},
    );
    test('known, me, unknown, name fallback', () {
      expect(people.isKnown('ann'), isTrue);
      expect(people.isKnown('me'), isTrue);
      expect(people.isMe('me'), isTrue);
      expect(people.isKnown('zed'), isFalse);
      expect(people.nameOf('ann'), 'Ann Rao');
      expect(people.nameOf('bob'), 'bob');
    });
  });
}
