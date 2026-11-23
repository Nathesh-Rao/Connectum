import 'package:connectum/features/forms/models/form_chat_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const none = FormChatMode.none;
  const always = FormChatMode.always;

  test('decide table', () {
    expect(FormChatRule.decide(null), none);
    expect(FormChatRule.decide('dm:ana'), none);
    expect(FormChatRule.decide('global'), none);
    expect(FormChatRule.decide('host:support'), none);
    expect(FormChatRule.decide('group:sales'), none);
    expect(FormChatRule.decide('group:care-ana'), always);
    expect(FormChatRule.decide('group:rec-ticket-1'), always);
  });

  test('chat is only ever a thread id, never dm:', () {
    expect(FormChatRule.chatFor('dm:ana'), isNull);
    expect(FormChatRule.chatFor('group:sales'), isNull);
    expect(FormChatRule.chatFor(null), isNull);
    expect(FormChatRule.chatFor('group:care-ana'), 'group:care-ana');
    expect(FormChatRule.chatFor('group:rec-x-1'), 'group:rec-x-1');
  });

  test('returns to workspace from a DM or team group only', () {
    expect(FormChatRule.returnsToWorkspace('dm:ana'), isTrue);
    expect(FormChatRule.returnsToWorkspace('group:sales'), isTrue);
    expect(FormChatRule.returnsToWorkspace('group:care-ana'), isFalse);
    expect(FormChatRule.returnsToWorkspace('group:rec-x-1'), isFalse);
    expect(FormChatRule.returnsToWorkspace('global'), isFalse);
    expect(FormChatRule.returnsToWorkspace(null), isFalse);
  });
}
