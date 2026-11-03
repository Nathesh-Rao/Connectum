import 'package:flutter/services.dart';

import '../../data/models/form_definition.dart';

/// How a typed field behaves: the keyboard, what may be typed, the longest
/// text and the action key. These only keep the input in the shapes the server
/// accepts; the server stays the authority and its messages still show.
class FormFormats {
  FormFormats._();

  /// Longest text or barcode the server takes.
  static const maxText = 5000;

  /// A text this long shows how much of the limit is used.
  static const counterFrom = 4500;

  /// The server's own bounds for the digits of a mobile number.
  static const mobileMinDigits = 7;
  static const mobileMaxDigits = 15;

  static TextInputType keyboard(FormFieldDef f) => switch (f.type) {
    'text' => f.isMultiline ? TextInputType.multiline : TextInputType.text,
    'email' => TextInputType.emailAddress,
    'url' => TextInputType.url,
    'mobile' => TextInputType.phone,
    'wholenumber' => TextInputType.numberWithOptions(signed: _isSigned(f)),
    'number' => TextInputType.numberWithOptions(
      decimal: true,
      signed: _isSigned(f),
    ),
    'location' => const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    _ => TextInputType.text,
  };

  /// A minus sign is typed only when the field can go below zero.
  static bool _isSigned(FormFieldDef f) => f.min == null || f.min! < 0;

  static List<TextInputFormatter> formatters(FormFieldDef f) =>
      switch (f.type) {
        'email' || 'url' => [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
        'mobile' => [const MobileFormatter()],
        'wholenumber' => [WholeFormatter(isSigned: _isSigned(f))],
        'number' => [DecimalFormatter(isSigned: _isSigned(f))],
        'location' => [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-\s]')),
        ],
        _ => const [],
      };

  static int? maxLength(FormFieldDef f) =>
      f.type == 'text' || f.type == 'barcode' ? maxText : null;

  static TextCapitalization capitalization(FormFieldDef f) =>
      f.type == 'text' ? TextCapitalization.sentences : TextCapitalization.none;

  /// Free-form text keeps the platform's suggestions; codes and addresses do
  /// not.
  static bool hasSuggestions(FormFieldDef f) =>
      f.type == 'text' || f.type == 'selection';

  /// `a mobile number as the server reads it`: digits and a leading plus.
  static String mobileClean(String text) {
    final t = text.trim();
    final digits = t.replaceAll(RegExp(r'\D'), '');
    return t.startsWith('+') ? '+$digits' : digits;
  }

  static int mobileDigits(String text) =>
      text.replaceAll(RegExp(r'\D'), '').length;
}

/// Digits, spaces and dashes, and a plus only as the first character; no more
/// digits than a number can have.
class MobileFormatter extends TextInputFormatter {
  const MobileFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (!RegExp(r'^\+?[0-9 \-]*$').hasMatch(text)) return oldValue;
    if (FormFormats.mobileDigits(text) > FormFormats.mobileMaxDigits) {
      return oldValue;
    }
    return newValue;
  }
}

/// Digits only (and a leading minus when the field can be negative).
class WholeFormatter extends TextInputFormatter {
  const WholeFormatter({required this.isSigned});

  final bool isSigned;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => RegExp(isSigned ? r'^-?\d*$' : r'^\d*$').hasMatch(newValue.text)
      ? newValue
      : oldValue;
}

/// Digits and one point, no thousands commas (and a leading minus when the
/// field can be negative).
class DecimalFormatter extends TextInputFormatter {
  const DecimalFormatter({required this.isSigned});

  final bool isSigned;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      RegExp(
        isSigned ? r'^-?\d*\.?\d*$' : r'^\d*\.?\d*$',
      ).hasMatch(newValue.text)
      ? newValue
      : oldValue;
}

/// A payment amount: digits and one point, never negative.
class AmountFormatter extends DecimalFormatter {
  const AmountFormatter() : super(isSigned: false);
}
