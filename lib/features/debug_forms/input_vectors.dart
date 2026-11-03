import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/debug/seed_sample_forms.dart';
import '../../data/models/form_definition.dart';
import '../../data/models/ids.dart';
import '../forms/form_formats.dart';
import '../forms/form_rules.dart';

/// One field of `sample_types` given some keystrokes (or a paste), and what
/// the input keeps, what the local check says and what would be sent.
class InputVector {
  const InputVector(
    this.field,
    this.keys, {
    required this.shown,
    this.message,
    this.sent,
    this.isPaste = false,
  });

  final String field;
  final String keys;
  final String shown;
  final String? message;
  final Object? sent;
  final bool isPaste;
}

class InputVectorResult {
  InputVectorResult(this.vector, this.shown, this.message, this.sent);

  final InputVector vector;
  final String shown;
  final String? message;
  final Object? sent;

  bool get isOk =>
      shown == vector.shown &&
      message == vector.message &&
      (vector.sent == null || jsonEncode(sent) == jsonEncode(vector.sent));

  String get line =>
      '${isOk ? 'PASS' : 'FAIL'}  ${vector.field}  '
      '${vector.isPaste ? 'paste' : 'type'} "${_clip(vector.keys)}"\n'
      '  keeps "${_clip(shown)}"${shown == vector.shown ? '' : ' (expected "${_clip(vector.shown)}")'}\n'
      '  says ${message ?? 'nothing'}${message == vector.message ? '' : ' (expected ${vector.message ?? 'nothing'})'}\n'
      '  sends ${jsonEncode(sent)}'
      '${vector.sent == null || jsonEncode(sent) == jsonEncode(vector.sent) ? '' : ' (expected ${jsonEncode(vector.sent)})'}';

  static String _clip(String s) =>
      s.length > 40 ? '${s.substring(0, 40)}… (${s.length})' : s;
}

class InputVectors {
  InputVectors._();

  static final _big = 'a' * 5001;

  static final vectors = <InputVector>[
    const InputVector(
      'email',
      'a sha@x.com',
      shown: 'asha@x.com',
      sent: 'asha@x.com',
    ),
    const InputVector(
      'email',
      'asha@',
      shown: 'asha@',
      message: 'Enter a valid email address.',
    ),
    const InputVector(
      'url',
      'example.com',
      shown: 'example.com',
      message: 'Enter a valid http(s) URL.',
    ),
    const InputVector(
      'url',
      'https://x.co/a b',
      shown: 'https://x.co/ab',
      sent: 'https://x.co/ab',
    ),
    const InputVector(
      'mobile',
      '98765 43210',
      shown: '98765 43210',
      sent: '9876543210',
    ),
    const InputVector(
      'mobile',
      '+91 98765-43210',
      shown: '+91 98765-43210',
      sent: '+919876543210',
    ),
    const InputVector(
      'mobile',
      '12+34',
      shown: '1234',
      message: 'Enter a valid mobile number.',
    ),
    const InputVector(
      'mobile',
      'abc123',
      shown: '123',
      message: 'Enter a valid mobile number.',
    ),
    const InputVector(
      'mobile',
      '1234567890123456',
      shown: '123456789012345',
      sent: '123456789012345',
    ),
    const InputVector(
      'mobile',
      '123456',
      shown: '123456',
      message: 'Enter a valid mobile number.',
    ),
    const InputVector('mobile', '1234567', shown: '1234567', sent: '1234567'),
    const InputVector(
      'mobileIntl',
      '9876543210',
      shown: '9876543210',
      message: 'Include the country code, e.g. +91...',
    ),
    const InputVector(
      'mobileIntl',
      '+919876543210',
      shown: '+919876543210',
      sent: '+919876543210',
    ),
    const InputVector('count', '4a2.5-', shown: '425', sent: 425),
    const InputVector(
      'count',
      '1001',
      shown: '1001',
      message: 'Must be at most 1000.',
    ),
    const InputVector('delta', '-12', shown: '-12', sent: -12),
    const InputVector(
      'delta',
      '-',
      shown: '-',
      message: 'Enter a whole number.',
    ),
    const InputVector('amount', '12.50', shown: '12.50', sent: 12.5),
    const InputVector('amount', '1,250.50', shown: '1250.50', sent: 1250.5),
    const InputVector('amount', '1.2.3', shown: '1.23', sent: 1.23),
    const InputVector('amount', '1,250.50', shown: '', isPaste: true),
    const InputVector(
      'place',
      '12.97, 77.59',
      shown: '12.97, 77.59',
      sent: {'lat': 12.97, 'lng': 77.59},
    ),
    const InputVector(
      'place',
      '95, 10',
      shown: '95, 10',
      message: 'Enter latitude and longitude, like 12.97, 77.59.',
    ),
    InputVector('text', _big, shown: 'a' * 5000, sent: 'a' * 5000),
    InputVector('code', _big, shown: 'a' * 5000, sent: 'a' * 5000),
  ];

  /// What the input would hold after the keys, one at a time (or all at once
  /// for a paste), through the field's own formatters.
  static String typed(FormFieldDef f, String keys, {required bool isPaste}) {
    final formatters = [
      ...FormFormats.formatters(f),
      if (FormFormats.maxLength(f) != null)
        LengthLimitingTextInputFormatter(FormFormats.maxLength(f)),
    ];
    var v = const TextEditingValue();
    TextEditingValue apply(TextEditingValue old, String text) {
      var next = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      for (final fmt in formatters) {
        next = fmt.formatEditUpdate(old, next);
      }
      return next;
    }

    if (isPaste) return apply(v, keys).text;
    for (final ch in keys.split('')) {
      v = apply(v, v.text + ch);
    }
    return v.text;
  }

  static List<InputVectorResult> run() {
    final def = SeedSampleForms.definitions()['sample_types']!;
    return [for (final v in vectors) _run(def, v), ..._payments(def)];
  }

  static InputVectorResult _run(FormDefinition def, InputVector v) {
    final f = def.fields.firstWhere((x) => x.name == v.field);
    final shown = typed(f, v.keys, isPaste: v.isPaste);
    final value = f.type == 'location' ? shown : shown;
    return InputVectorResult(
      v,
      shown,
      FormRules.check(f, value),
      FormRules.toSent(f, value),
    );
  }

  /// Payments are chosen, not typed: the values the chips and the amount
  /// would hold.
  static List<InputVectorResult> _payments(FormDefinition def) {
    final f = def.fields.firstWhere((x) => x.name == 'pay');
    InputVectorResult one(
      String name,
      Map<String, String> value,
      String? message,
      Object? sent,
    ) {
      final v = InputVector(
        'pay',
        name,
        shown: idText(value['amount']),
        message: message,
        sent: sent,
      );
      return InputVectorResult(
        v,
        idText(value['amount']),
        FormRules.check(f, value),
        FormRules.toSent(f, value),
      );
    }

    return [
      one(
        'paid, no amount',
        {'amount': '', 'status': 'paid'},
        'Enter the amount.',
        null,
      ),
      one(
        'paid, no method',
        {'amount': '10', 'status': 'paid'},
        'Choose how it was paid.',
        null,
      ),
      one(
        'method not on the list',
        {'amount': '10', 'method': 'Bitcoin', 'status': 'pending'},
        'Choose a payment method from the list.',
        null,
      ),
      one(
        'paid by upi',
        {'amount': '10', 'method': 'upi', 'status': 'paid'},
        null,
        {'amount': 10, 'method': 'UPI', 'status': 'paid'},
      ),
      one(
        'pay later, no method',
        {'amount': '99.5', 'status': 'pending'},
        null,
        {'amount': 99.5, 'status': 'pending'},
      ),
    ];
  }
}
