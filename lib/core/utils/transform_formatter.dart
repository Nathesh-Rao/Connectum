import 'package:flutter/services.dart';

/// Rewrites what is typed or pasted through [transform] (strip characters,
/// cut to a limit), keeping the caret where it was in the kept text.
class TransformFormatter extends TextInputFormatter {
  const TransformFormatter(this.transform);

  final String Function(String text) transform;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = transform(newValue.text);
    if (text == newValue.text) return newValue;
    final caret = newValue.selection.baseOffset;
    final offset = caret < 0 || caret > newValue.text.length
        ? text.length
        : transform(newValue.text.substring(0, caret)).length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset.clamp(0, text.length)),
    );
  }
}
