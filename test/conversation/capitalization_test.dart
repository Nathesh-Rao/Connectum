import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _field(String path, String marker) {
  final s = File(path).readAsStringSync();
  final i = s.indexOf(marker);
  expect(i, greaterThan(-1), reason: marker);
  return s.substring(i, s.indexOf('),', i));
}

void main() {
  test('composers capitalise sentences', () {
    expect(
      _field(
        'lib/features/conversation/widgets/conversation_composer.dart',
        'AppTextField(',
      ),
      contains('TextCapitalization.sentences'),
    );
    expect(
      _field(
        'lib/features/workspace/widgets/workspace_composer.dart',
        'AppTextField(',
      ),
      contains('TextCapitalization.sentences'),
    );
  });

  test('name fields capitalise words', () {
    expect(
      _field('lib/features/new_group/new_group_view.dart', 'AppTextField('),
      contains('TextCapitalization.words'),
    );
    expect(
      _field(
        'lib/features/chats/widgets/record_rename_sheet.dart',
        'AppTextField(',
      ),
      contains('TextCapitalization.words'),
    );
  });

  test('search, code and email fields stay none', () {
    for (final p in [
      'lib/features/chats/widgets/new_chat_sheet.dart',
      'lib/features/conversation/widgets/forward_sheet.dart',
      'lib/features/chat_info/widgets/chat_info_members.dart',
      'lib/features/invite_code/invite_code_view.dart',
      'lib/features/verification/verification_view.dart',
    ]) {
      expect(
        _field(p, 'AppTextField('),
        isNot(contains('TextCapitalization.s')),
        reason: p,
      );
    }
    expect(
      File('lib/core/widgets/app_text_field.dart').readAsStringSync(),
      contains('textCapitalization = TextCapitalization.none'),
    );
  });
}
