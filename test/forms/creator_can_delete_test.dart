import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/form_definition.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:flutter_test/flutter_test.dart';

FormCardData _card(String by) => FormCardData(
  id: '12',
  caption: 'Leave',
  structure: 'leave',
  scope: 'user',
  by: by,
  ts: 1,
  entries: const [],
);

FormDefinition _form(Map<String, dynamic> extra) => FormDefinition.fromMap(
  'leave',
  'user',
  {'caption': 'Leave', 'owner': 'boss', ...extra},
);

void main() {
  group('creatorCanDelete on a record card', () {
    test('missing field, true and no definition keep Delete', () {
      expect(_card('alex').canDelete('alex'), isTrue);
      expect(_card('alex').canDelete('alex', form: _form({})), isTrue);
      expect(
        _card(
          'alex',
        ).canDelete('alex', form: _form({'creatorCanDelete': true})),
        isTrue,
      );
    });

    test('false hides Delete from the author', () {
      expect(
        _card(
          'alex',
        ).canDelete('alex', form: _form({'creatorCanDelete': false})),
        isFalse,
      );
    });

    test('false keeps it for the form owner; other values mean on', () {
      expect(
        _card(
          'boss',
        ).canDelete('boss', form: _form({'creatorCanDelete': false})),
        isTrue,
      );
      expect(
        _card(
          'alex',
        ).canDelete('alex', form: _form({'creatorCanDelete': 'no'})),
        isTrue,
      );
    });
  });

  group('how the flag arrives', () {
    test('a structures entry keeps it only when false, with the owner', () {
      final off = FormDefinition.captionsJson({
        'caption': 'Leave',
        'fields': {'a': 'A'},
        'creatorCanDelete': false,
        'owner': 'boss',
      });
      final d = FormDefinition.parse('leave', 'user', off);
      expect(d.creatorCanDelete, isFalse);
      expect(d.mayDeleteOwn('alex'), isFalse);
      expect(d.mayDeleteOwn('Boss'), isTrue);
      final on = FormDefinition.captionsJson({'caption': 'Leave'});
      expect(
        FormDefinition.parse('leave', 'user', on).creatorCanDelete,
        isTrue,
      );
    });

    test('a Smart View source reads it', () {
      expect(SvSource.tryParse({'name': 'a'})!.creatorCanDelete, isTrue);
      expect(
        SvSource.tryParse({
          'name': 'a',
          'creatorCanDelete': true,
        })!.creatorCanDelete,
        isTrue,
      );
      expect(
        SvSource.tryParse({
          'name': 'a',
          'creatorCanDelete': false,
        })!.creatorCanDelete,
        isFalse,
      );
    });
  });
}
