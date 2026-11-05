import '../../core/widgets/app_highlight_text.dart';

/// Self-test of the sentence builder behind [AppHighlightText]: where the
/// names go, and that a name is never read as a template.
class HighlightVectors {
  HighlightVectors(this._check);

  final Future<void> Function(String name, Future<String?> Function() body)
  _check;

  static String _show(List<HighlightPart> parts) =>
      parts.map((p) => p.isHighlighted ? '[${p.text}]' : p.text).join();

  Future<void> run() async {
    Future<void> expect(
      String name,
      String template,
      Map<String, String> values,
      String want,
    ) => _check('highlight: $name', () async {
      final got = _show(AppHighlightText.parts(template, values));
      return got == want ? null : got;
    });

    await expect(
      'placeholders at the start, middle and end',
      '{you} and {name} are already associates',
      {'you': 'You', 'name': 'amr'},
      '[You] and [amr] are already associates',
    );
    await expect('placeholder at the end', 'Connect with {name}', {
      'name': 'Ann',
    }, 'Connect with [Ann]');
    await expect('placeholder only', '{name}', {'name': 'Ann'}, '[Ann]');
    await expect(
      'a name with braces is not a template',
      'Hi {name} and {you}',
      {'name': '{you}', 'you': 'You'},
      'Hi [{you}] and [You]',
    );
    await expect('a name with a dollar sign and a quote', 'Hi {name}.', {
      'name': r'A$1 "B"',
    }, r'Hi [A$1 "B"].');
    await expect('an empty name adds no run', 'Hi {name}.', {
      'name': '',
    }, 'Hi .');
    await expect(
      'a placeholder without a value stays',
      'Hi {other} {name}',
      {'name': 'Ann'},
      'Hi {other} [Ann]',
    );
    await expect('plain braces stay', 'Use {} or {x y} here', {
      'name': 'Ann',
    }, 'Use {} or {x y} here');
    await expect('no placeholders', 'Nothing to mark', {
      'name': 'Ann',
    }, 'Nothing to mark');
    await _check('highlight: a very long name is one run', () async {
      final long = 'x' * 300;
      final parts = AppHighlightText.parts('Hi {name}!', {'name': long});
      return parts.length == 3 &&
              parts[1].isHighlighted &&
              parts[1].text == long
          ? null
          : '${parts.length} runs';
    });
    await _check('highlight: the plain sentence reads whole', () async {
      final plain = AppHighlightText.plain('{you} and {name} are here', {
        'you': 'You',
        'name': 'amr',
      });
      return plain == 'You and amr are here' ? null : plain;
    });
  }
}
