import 'package:connectum/core/utils/forwarded_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain text is not a forward', () {
    final f = ForwardedText.parse('hello');
    expect(f.isForwarded, isFalse);
    expect(f.text, 'hello');
  });

  test('forwarder only', () {
    final f = ForwardedText.parse('↪ [Forwarded by Bob]: hi');
    expect(f.isForwarded, isTrue);
    expect(f.forwardedBy, 'Bob');
    expect(f.originalFrom, isNull);
    expect(f.text, 'hi');
  });

  test('forwarder and original author', () {
    final f = ForwardedText.parse('↪ [Forwarded by Bob • from Carol]: hi');
    expect(f.forwardedBy, 'Bob');
    expect(f.originalFrom, 'Carol');
    expect(f.text, 'hi');
  });

  test('missing name falls back to the sender; case-insensitive', () {
    final f = ForwardedText.parse('↪ [forwarded]: hi', sender: 'ann');
    expect(f.isForwarded, isTrue);
    expect(f.forwardedBy, 'ann');
    expect(f.text, 'hi');
  });

  test('multiline text is kept whole', () {
    final f = ForwardedText.parse('↪ [Forwarded by Bob]: one\ntwo\n\nthree');
    expect(f.text, 'one\ntwo\n\nthree');
  });

  test('a forward of a forward is read as the outer line only', () {
    final f = ForwardedText.parse(
      '↪ [Forwarded by Bob]: ↪ [Forwarded by Ann • from Carol]: hi',
    );
    expect(f.forwardedBy, 'Bob');
    expect(f.text, '↪ [Forwarded by Ann • from Carol]: hi');
  });

  test('an attachment tag after the line stays in the text', () {
    final f = ForwardedText.parse('↪ [Forwarded by Bob]: [ATTACHMENT:{}]');
    expect(f.text, '[ATTACHMENT:{}]');
  });
}
