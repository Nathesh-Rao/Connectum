import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File(
    'lib/features/conversation/widgets/conversation_composer.dart',
  ).readAsStringSync();

  test('composer shows the Message placeholder and no lock in the field', () {
    expect(src, contains("hint: 'Message'"));
    expect(src, isNot(contains('for commands')));
    expect(src, isNot(contains('new message')));
    expect(src, isNot(contains('Icons.lock')));
  });

  test('attach button uses the attachements PNG', () {
    expect(src, contains('assets/icons/chat/attachements.png'));
  });

  test('forms button uses the add_forms PNG', () {
    expect(src, contains('assets/icons/chat/add_forms.png'));
    expect(src, isNot(contains('Icons.grid_view')));
  });
}
