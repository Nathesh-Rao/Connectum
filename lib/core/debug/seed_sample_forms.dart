import 'dart:convert';

import '../../data/models/form_definition.dart';
import '../../data/models/form_option.dart';
import '../../data/models/slot_day.dart';

/// The `sample_*` forms for `SEED_UI=1` (debug only): the definitions from
/// the backend pack's `docs/sample-forms`, so every state can be tried with
/// no server. `sample_cascade` is the pack's form with the options and
/// `optionProps` the server would resolve, made up here.
class SeedSampleForms {
  SeedSampleForms._();

  static const names = [
    'sample_calc',
    'sample_rule',
    'sample_grid',
    'sample_dates',
    'sample_condition',
    'sample_cascade',
    'sample_types',
    'sample_file',
    'sample_selection',
    'sample_fetch',
    'sample_toggle',
    'sample_colour',
    'sample_slot',
  ];

  static List<FormOption> options() => [
    for (var i = 0; i < names.length; i++)
      FormOption(
        id: names[i],
        caption: _caption(names[i]),
        type: 'data_input',
        target: names[i],
        targetScope: 'user',
        category: 'data_input',
        order: 100 + i,
      ),
  ];

  static String _caption(String name) =>
      (jsonDecode(_json[name]!) as Map)['caption'] as String;

  static Map<String, FormDefinition> definitions() => {
    for (final n in names)
      n: FormDefinition.fromMap(n, 'user', jsonDecode(_json[n]!) as Map),
  };

  static const _json = {
    'sample_calc':
        r'''{"name":"sample_calc","caption":"Sample: calculations (auto values)","fields":[{"name":"qty","type":"wholenumber","caption":"Quantity","required":true,"min":1},{"name":"price","type":"number","caption":"Price","required":true,"min":0},{"name":"total","type":"number","caption":"Total","calc":{"expr":"qty*price"}},{"name":"age","type":"wholenumber","caption":"Age"},{"name":"group","type":"list","caption":"Group","options":["Adult","Minor"],"calc":{"expr":"IIF(age>18,\"Adult\",\"Minor\")"}},{"name":"stamp","type":"wholenumber","caption":"Reference number (hidden, worked out)","hidden":true,"calc":{"expr":"qty*1000+age"}}]}''',
    'sample_rule':
        r'''{"name":"sample_rule","caption":"Sample: rules (checks the app makes)","fields":[{"name":"phone","type":"text","caption":"Phone (10 digits)","rule":{"expr":"Length(phone)=10","message":"The phone must have 10 digits"}},{"name":"age","type":"wholenumber","caption":"Age (18 or more)","rule":{"expr":"age>=18","message":"You must be 18 or older"}},{"name":"email","type":"text","caption":"Email","rule":{"expr":"CheckEmail(email)","message":"That is not an email address"}},{"name":"start","type":"date","caption":"Start date"},{"name":"finish","type":"date","caption":"Finish date (not before the start)","rule":{"expr":"Val(finish)>=Val(start)","message":"The finish cannot be before the start"}}]}''',
    'sample_grid':
        r'''{"name":"sample_grid","caption":"Sample: a grid with a total","sections":[{"name":"items","caption":"Items","grid":true},{"name":"summary","caption":"Summary"}],"fields":[{"name":"item","type":"text","caption":"Item","section":"items","required":true},{"name":"qty","type":"wholenumber","caption":"Quantity","section":"items","required":true,"min":1},{"name":"rate","type":"number","caption":"Rate","section":"items","required":true,"min":0},{"name":"lineTotal","type":"number","caption":"Line total","section":"items","calc":{"expr":"qty*rate"}},{"name":"customer","type":"text","caption":"Customer","section":"summary","required":true},{"name":"grandTotal","type":"number","caption":"Grand total","section":"summary","calc":{"expr":"Total(lineTotal)"}}]}''',
    'sample_dates':
        r'''{"name":"sample_dates","caption":"Sample: dates and times","fields":[{"name":"joined","type":"date","caption":"Date joined (not in the future)","max":"2099-12-31","min":"2000-01-01"},{"name":"today","type":"date","caption":"Today (filled in)","defaultNow":true,"readOnly":true},{"name":"at","type":"time","caption":"Time"},{"name":"nextWeek","type":"date","caption":"A week after the date joined","calc":{"expr":"AddToDate(joined,7)"}}]}''',
    'sample_condition':
        r'''{"name":"sample_condition","caption":"Sample: conditions (show a field only when)","fields":[{"name":"hasCar","type":"toggle","caption":"Do you have a car?"},{"name":"carNumber","type":"text","caption":"Car number","required":true,"condition":{"field":"hasCar","op":"eq","value":"Yes"}},{"name":"kind","type":"list","caption":"Kind of leave","options":["Sick","Casual","Other"],"required":true},{"name":"reason","type":"text","caption":"Please say why","required":true,"condition":{"any":[{"field":"kind","op":"eq","value":"Other"},{"field":"kind","op":"eq","value":"Sick"}]}}]}''',
    'sample_cascade':
        r'''{"name":"sample_cascade","caption":"Sample: cascading drop downs (the second depends on the first)","fields":[{"name":"department","type":"list","caption":"Department","source":"departments","required":true,"options":["Sales","Ops"]},{"name":"person","type":"list","caption":"Person (of that department)","source":"people","dependsOn":{"field":"department","prop":"department"},"options":["asha","ravi","meera"],"optionLabels":{"asha":"Asha Rao","ravi":"Ravi Kumar","meera":"Meera Iyer"},"optionProps":{"asha":"Sales","ravi":"Ops","meera":["Sales","Ops"]}}]}''',
    'sample_types':
        r'''{"name":"sample_types","caption":"Sample: one field of every basic kind (the value each one is saved as)","fields":[{"name":"text","type":"text","caption":"Short text"},{"name":"notes","type":"text","caption":"Large text","multiline":true},{"name":"email","type":"email","caption":"Email"},{"name":"url","type":"url","caption":"Web address"},{"name":"mobile","type":"mobile","caption":"Mobile"},{"name":"mobileIntl","type":"mobile","caption":"Mobile with country code","withCountryCode":true},{"name":"count","type":"wholenumber","caption":"Whole number","min":0,"max":1000},{"name":"delta","type":"wholenumber","caption":"Whole number (can be negative)"},{"name":"amount","type":"number","caption":"Decimal number"},{"name":"day","type":"date","caption":"Date"},{"name":"clock","type":"time","caption":"Time"},{"name":"place","type":"location","caption":"Location"},{"name":"code","type":"barcode","caption":"Barcode or QR"},{"name":"pay","type":"payment","caption":"Payment","methods":["Cash","Card","UPI"],"currency":"INR"},{"name":"invoice","type":"autogenerate","caption":"Invoice number (made by the server)","prefix":"INV-","digits":4}]}''',
    'sample_file':
        r'''{"name":"sample_file","caption":"Sample: files","fields":[{"name":"photo","type":"file","caption":"One photo","required":true},{"name":"documents","type":"file","caption":"Up to ten documents","multi":true}]}''',
    'sample_selection':
        r'''{"name":"sample_selection","caption":"Sample: choices from another form, and a fill","fields":[{"name":"pick","type":"selection","caption":"Colour (from the sample_colour records)","source":{"type":"query","form":"sample_colour","valueField":"colour","labelField":"colour","columns":["code"]},"required":true},{"name":"picks","type":"selection","caption":"Several colours","multi":true,"source":{"type":"query","form":"sample_colour","valueField":"colour","labelField":"colour"}},{"name":"pickCode","type":"fill","caption":"Code (filled from the colour you picked)","fillFrom":"pick","sourceProp":"code"}]}''',
    'sample_fetch':
        r'''{"name":"sample_fetch","caption":"Sample: fetch (a field filled from another form)","fields":[{"name":"colour","type":"list","caption":"Colour","options":["Red","Green","Blue"],"required":true},{"name":"colourCode","type":"text","caption":"Code of the colour (fetched)","fetch":{"type":"query","form":"sample_colour","valueField":"code","labelField":"code","where":{"field":"colour","op":"eq","param":"colourName"},"params":{"colourName":{"field":"colour"}}}}]}''',
    'sample_toggle':
        r'''{"name":"sample_toggle","caption":"Sample: switches (Yes or No)","fields":[{"name":"agree","type":"toggle","caption":"I agree","required":true},{"name":"newsletter","type":"toggle","caption":"Send me the newsletter","default":"No"}]}''',
    'sample_colour':
        r'''{"name":"sample_colour","caption":"Sample: colours (a small list the other samples read)","fields":[{"name":"colour","type":"text","caption":"Colour","required":true},{"name":"code","type":"text","caption":"Code"}]}''',
    'sample_slot':
        r'''{"name":"sample_slot","caption":"Sample: a booking time (made up for this build; the pack has none)","fields":[{"name":"doctor","type":"list","caption":"Doctor","options":["asha","ravi"],"optionLabels":{"asha":"Asha Rao","ravi":"Ravi Kumar"},"required":true},{"name":"visit","type":"slot","caption":"Visit time","of":"doctor","required":true}]}''',
  };

  static const _colours = [
    {'value': 'Red', 'label': 'Red', 'code': 'R-01'},
    {'value': 'Green', 'label': 'Green', 'code': 'G-02'},
    {'value': 'Blue', 'label': 'Blue', 'code': 'B-03'},
  ];

  /// What `form.options` would answer for the sample selection and fetch
  /// fields. `pick` shows a kept list marked as old, `picks` has nothing kept
  /// (so it is disabled), to see both states without a server.
  static FieldRows? fieldRows(
    String form,
    String field,
    Map<String, dynamic> values,
  ) {
    if (form == 'sample_fetch') {
      final colour = (values['colour'] ?? '').toString();
      if (colour.isEmpty) return const FieldRows(isWaiting: true);
      for (final c in _colours) {
        if (c['value']!.toLowerCase() == colour.toLowerCase()) {
          return FieldRows(
            choices: [
              FormChoice(
                c['code']!,
                c['code']!,
                raw: {...c, 'value': c['code']!},
              ),
            ],
          );
        }
      }
      return const FieldRows();
    }
    if (form == 'sample_selection' && field == 'picks') return null;
    final rows = FieldRows(
      choices: [
        for (final c in _colours) FormChoice(c['value']!, c['label']!, raw: c),
      ],
    );
    return form == 'sample_selection' ? rows.asStale() : rows;
  }

  /// Fourteen days of times, some already taken.
  static List<SlotDay> slotDays() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return [
      for (var d = 1; d <= 14; d++)
        if ((now.add(Duration(days: d))).weekday != DateTime.sunday)
          SlotDay(
            '${now.add(Duration(days: d)).year}-${two(now.add(Duration(days: d)).month)}-${two(now.add(Duration(days: d)).day)}',
            [
              for (var h = 9; h < 13; h++)
                for (final m in const [0, 30])
                  SlotTime('${two(h)}:${two(m)}', (h + m + d) % 4 != 0),
            ],
          ),
    ];
  }
}
