import 'package:connectum/data/profile/status_text.dart';
import 'package:flutter_test/flutter_test.dart';

bool _hasLoneSurrogate(String s) {
  final units = s.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    final isHigh = u >= 0xD800 && u <= 0xDBFF;
    final isLow = u >= 0xDC00 && u <= 0xDFFF;
    if (isHigh &&
        (i + 1 >= units.length ||
            units[i + 1] < 0xDC00 ||
            units[i + 1] > 0xDFFF)) {
      return true;
    }
    if (isLow && (i == 0 || units[i - 1] < 0xD800 || units[i - 1] > 0xDBFF)) {
      return true;
    }
  }
  return false;
}

void main() {
  // The rule used: the server counts the characters of its decoded string
  // (`length/1`), so this counts Unicode code points. An emoji is one; a
  // family emoji is five (three people and two joiners).
  group('140 limit counts code points', () {
    test('140 plain characters pass, 141 are cut to 140', () {
      expect(StatusText.typed('a' * 140), 'a' * 140);
      expect(StatusText.typed('a' * 141), 'a' * 140);
      expect(StatusText.length('a' * 140), 140);
    });

    test('an emoji at the boundary is one character: 139 + emoji passes', () {
      final text = '${'a' * 139}😀';
      expect(text.length, 141, reason: 'UTF-16 units, what the web counts');
      expect(StatusText.length(text), 140);
      expect(StatusText.typed(text), text);
    });

    test('140 + an emoji drops the whole emoji, never half of it', () {
      final cut = StatusText.typed('${'a' * 140}😀');
      expect(cut, 'a' * 140);
      expect(_hasLoneSurrogate(cut), isFalse);
    });

    test('a multi-part emoji is cut between its parts, not inside a pair', () {
      final family = '👨‍👩‍👧';
      final cut = StatusText.typed('${'a' * 139}$family');
      expect(StatusText.length(cut), 140);
      expect(_hasLoneSurrogate(cut), isFalse);
      expect(cut.startsWith('a' * 139), isTrue);
    });

    test('non-Latin text counts characters, not bytes', () {
      expect(StatusText.typed('अ' * 140), 'अ' * 140);
      expect(StatusText.typed('é' * 141), 'é' * 140);
    });
  });

  group('typed and sent text', () {
    test('control characters and newlines are removed as typed', () {
      expect(StatusText.typed('a\nb\tc\u0000d\u007Fe\r'), 'abcde');
    });

    test('a pasted block with newlines becomes one line', () {
      expect(StatusText.typed('line one\nline two'), 'line oneline two');
    });

    test('toSend trims and cuts; spaces only means clear', () {
      expect(StatusText.toSend('  hi  '), 'hi');
      expect(StatusText.toSend('   '), '');
      expect(StatusText.toSend('${'a' * 150} '), 'a' * 140);
    });

    test('a status starting with a slash is kept as it is', () {
      expect(StatusText.toSend('/away for now'), '/away for now');
    });

    test('the counter turns bold from 130', () {
      expect(StatusText.warnFrom, 130);
      expect(StatusText.maxLength, 140);
    });
  });
}
