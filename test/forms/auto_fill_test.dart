import 'package:connectum/data/form_logic/form_logic_service.dart';
import 'package:connectum/data/form_logic/form_logic_values.dart';
import 'package:connectum/data/models/form_definition.dart';
import 'package:connectum/data/repositories/form_file_repository.dart';
import 'package:connectum/data/repositories/form_options_repository.dart';
import 'package:connectum/data/repositories/submission_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/features/forms/form_controller.dart';
import 'package:connectum/features/forms/form_rules.dart';
import 'package:connectum/features/forms/models/field_input.dart';
import 'package:connectum/features/forms/models/form_launch.dart';
import 'package:connectum/features/forms/widgets/form_field_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Subs extends Fake implements SubmissionRepository {}

class _Options extends Fake implements FormOptionsRepository {}

class _Logic extends Fake implements FormLogicService {}

class _Files extends Fake implements FormFileRepository {}

class _Store extends Fake implements SessionStore {}

FormDefinition _form(List<Map<String, dynamic>> fields) =>
    FormDefinition.fromMap('f', 'user', {'caption': 'F', 'fields': fields});

FormFieldDef _field(Map<String, dynamic> raw) => _form([
  {'name': 'x', 'caption': 'X', ...raw},
]).fields.single;

void main() {
  const kinds = [
    'text',
    'email',
    'url',
    'mobile',
    'wholenumber',
    'number',
    'date',
    'time',
  ];

  group('the parser', () {
    test('a form saved now: its own kind plus autoFill is an Auto Fill', () {
      for (final kind in kinds) {
        final f = _field({
          'type': kind,
          'autoFill': true,
          'fillFrom': 'item',
          'sourceProp': 'price',
        });
        expect(f.isAutoFill, isTrue, reason: kind);
        expect(f.kind, kind);
        expect(f.raw['fillFrom'], 'item');
        expect(FormRules.isSupported(f), isTrue);
      }
    });

    test('an old form: type fill reads as text', () {
      final f = _field({'type': 'fill', 'fillFrom': 'item'});
      expect(f.isAutoFill, isTrue);
      expect(f.kind, 'text');
    });

    test('autoFill false, "no", an object or another kind is ordinary', () {
      for (final v in [false, 'no', 'true', <String, dynamic>{}]) {
        expect(_field({'type': 'date', 'autoFill': v}).isAutoFill, isFalse);
      }
      final toggle = _field({'type': 'toggle', 'autoFill': true});
      expect(toggle.isAutoFill, isFalse);
      expect(toggle.kind, 'toggle');
      expect(_field({'type': 'date'}).kind, 'date');
    });

    test('never required, even when the form says so', () {
      expect(
        _field({'type': 'date', 'autoFill': true, 'required': true}).isRequired,
        isFalse,
      );
      expect(_field({'type': 'fill', 'required': true}).isRequired, isFalse);
      expect(_field({'type': 'date', 'required': true}).isRequired, isTrue);
    });
  });

  group('the rules', () {
    test('no required check and no date, number, email or url check', () {
      for (final kind in kinds) {
        final f = _field({'type': kind, 'autoFill': true, 'required': true});
        expect(FormRules.check(f, null), isNull, reason: kind);
        expect(FormRules.check(f, 'not a $kind'), isNull, reason: kind);
      }
      final date = _field({'type': 'date', 'required': true});
      expect(FormRules.check(date, 'not a date'), isNotNull);
    });

    test('the value is sent and kept as text', () {
      for (final kind in kinds) {
        final f = _field({'type': kind, 'autoFill': true});
        expect(FormRules.toSent(f, '12 Mar 2026'), '12 Mar 2026');
        expect(FormRules.toSent(f, '1,200'), '1,200');
        expect(FormRules.isSent(f), isTrue);
      }
    });

    test('a hidden Auto Fill is still made for the person and sent', () {
      final f = _field({'type': 'date', 'autoFill': true});
      expect(FormRules.isMadeFor(f), isTrue);
      expect(FormRules.toSent(f, '2026-03-12'), '2026-03-12');
    });

    test('the logic gets it as text, never converted as a date', () {
      final out = FormLogicValues.toLogic(
        [
          {'name': 'd', 'type': 'date', 'autoFill': true},
        ],
        const {},
        {'d': '12/03/2026 (Thu)'},
      );
      expect(out['d'], '12/03/2026 (Thu)');
    });
  });

  group('the screen', () {
    FormController controller() => FormController(
      launch: FormLaunch(name: 'f', scope: 'user', caption: 'F'),
      submissions: _Subs(),
      options: _Options(),
      store: _Store(),
      connectivity: FakeConnectivity(),
      logic: _Logic(),
      files: _Files(),
    );

    for (final kind in kinds) {
      testWidgets('$kind: read only, plain text, no keyboard or picker', (
        tester,
      ) async {
        final def = _field({
          'type': kind,
          'autoFill': true,
          'required': true,
          'fillFrom': 'item',
        });
        final input = FieldInput(def, 'copied value');
        addTearDown(input.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FormFieldRow(controller: controller(), input: input),
            ),
          ),
        );
        expect(find.text('copied value'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(EditableText), findsNothing);
        expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
        expect(find.text(' *'), findsNothing, reason: 'never marked required');
        await tester.tap(find.text('copied value'));
        await tester.pump();
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.byType(TimePickerDialog), findsNothing);
      });
    }
  });

  group('Smart View', () {
    test('an Auto Fill column is a text column whatever its kind', () {
      for (final kind in kinds) {
        final field = SvField.tryParse({
          'name': 'x',
          'caption': 'X',
          'type': kind,
          'autoFill': true,
        })!;
        expect(field.type, 'text', reason: kind);
        expect(SmartViewColumns.typeOf(field.type), SvColType.text);
      }
      expect(SvField.tryParse({'name': 'x', 'type': 'fill'})!.type, 'text');
      expect(
        SmartViewColumns.typeOf(
          SvField.tryParse({'name': 'd', 'type': 'date'})!.type,
        ),
        SvColType.date,
      );
    });
  });
}
