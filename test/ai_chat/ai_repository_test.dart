import 'dart:async';
import 'dart:io';

import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_prompt.dart';
import 'package:connectum/data/ai/ai_relay.dart';
import 'package:connectum/data/ai/ai_repository_impl.dart';
import 'package:connectum/data/ai/ai_transcript.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Messages extends Fake implements MessageRepository {
  List<Message> rows = [];
  int reads = 0;
  int settled = 0;

  @override
  Future<void> settleDecrypt() async => settled++;

  @override
  Future<List<Message>> readFor(String org, String user, String convId) async {
    reads++;
    return rows;
  }
}

Message msg(String id, String text, int ts, {bool isMine = false}) => Message(
  msgId: id,
  convId: 'dm:ana',
  sender: isMine ? 'me' : 'ana',
  isMine: isMine,
  text: text,
  ts: ts,
  status: MessageStatus.sent,
);

const claude = AiAgent(
  id: 'claude',
  name: 'Claude',
  provider: 'anthropic',
  model: 'claude-haiku-5-5',
);

Map<String, dynamic> ok(String text) => {
  'status': 200,
  'body': {
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
  'modelUsed': 'claude-haiku-5-5',
  'fellBack': false,
};

class Rig {
  Rig() {
    socket.goOnline();
    messages.rows = [
      msg(
        '1',
        'Shall we send the quote today?',
        DateTime(2026, 11, 9, 9, 12).millisecondsSinceEpoch,
      ),
      msg(
        '2',
        'Yes, after lunch',
        DateTime(2026, 11, 9, 9, 15).millisecondsSinceEpoch,
        isMine: true,
      ),
    ];
    repo = AiRepositoryImpl(
      socket,
      FakeStore(),
      messages,
      statusOf: (id) => id == '12' ? 'Approved' : null,
      displayNameOf: (u) => u == 'me' ? 'Maya Rao' : u,
      clock: () => DateTime(2026, 11, 11, 10),
    );
  }

  final socket = FakeSocket();
  final messages = _Messages();
  late final AiRepositoryImpl repo;

  Future<AiSummaryChunk> ask({
    AiAgent agent = claude,
    AiRange range = AiRange.everything,
  }) => repo
      .summarize(
        AiSummaryRequest(
          chatId: 'dm:ana',
          title: 'Ana',
          range: range,
          agent: agent,
        ),
      )
      .single;
}

void main() {
  group('setup', () {
    test('one agent or more is ready, with the agents', () async {
      final r = Rig();
      r.socket.answers['ai.agents'] = {
        'agents': [
          {
            'id': 'claude',
            'name': 'Claude',
            'alias': 'claude',
            'provider': 'anthropic',
            'model': 'm',
            'modelChoice': false,
            'extra': 1,
          },
          {'id': 'gpt', 'name': 'GPT', 'provider': 'openai'},
        ],
      };
      final setup = await r.repo.getSetupState();
      expect(setup.state, AiSetupState.ready);
      expect(setup.agents.map((a) => a.id), ['claude', 'gpt']);
      expect(setup.agents.first.provider, 'anthropic');
      expect(setup.agents.first.alias, 'claude');
      expect(setup.agents.first.hasModelChoice, isFalse);
    });

    test('no agents is not set up', () async {
      final r = Rig();
      r.socket.answers['ai.agents'] = {'agents': <dynamic>[]};
      expect((await r.repo.getSetupState()).state, AiSetupState.notSetUp);
    });

    test('offline and a lost connection are the offline error', () async {
      final r = Rig();
      r.socket.goOffline();
      await expectLater(
        r.repo.getSetupState(),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.offline),
        ),
      );
    });

    test('agents changed fires on the event and on reconnect', () async {
      final r = Rig();
      var fired = 0;
      r.repo.agentsChanged.listen((_) => fired++);
      r.repo.onEvent({
        'type': 'sd_event',
        'event': 'ai_agents_changed',
        'data': {'action': 'saved'},
      });
      r.repo.onEvent({'type': 'sd_event', 'event': 'task_updated'});
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1);
      r.socket.emitOnline();
      await Future<void>.delayed(Duration.zero);
      expect(fired, 2);
    });
  });

  group('summarize', () {
    test(
      'sends the transcript through assistant.relay, one final event',
      () async {
        final r = Rig();
        r.socket.answers['assistant.relay'] = ok(
          '**Summary**\n- quote after lunch',
        );
        final chunk = await r.ask();
        expect(chunk.isFinal, isTrue);
        expect(chunk.text, startsWith('**Summary**'));
        expect(chunk.messageCount, 2);
        final call = r.socket.calls.single;
        expect(call.action, 'assistant.relay');
        expect(call.args['agent'], 'claude');
        final payload = call.args['payload'] as Map;
        expect(payload['max_tokens'], 1800);
        expect(payload['temperature'], 0);
        expect(payload.containsKey('stream'), isFalse);
        final question =
            ((payload['messages'] as List).single as Map)['content'] as String;
        expect(
          question,
          'Summarise my private chat "Ana", from the beginning. Give the main '
          'points, the decisions made, anything still open or unanswered, and '
          'the action items with who owns each. Keep it short and in the order '
          'things happened where that matters.',
        );
        // The transcript is inside the system prompt as CHAT IN FOCUS.
        final system = payload['system'] as String;
        expect(
          system,
          startsWith(
            'You are the friendly My Workspace assistant for Maya Rao. '
            'Today is Wed Nov 11 2026.\n\n'
            "You can read the user's own chats",
          ),
        );
        expect(
          system,
          contains(
            'Be warm, concise and clear.\n\nAnswer style (follow it in every '
            'answer):',
          ),
        );
        expect(
          system,
          endsWith(
            'CHAT IN FOCUS (read earlier in this conversation: "Ana")\n'
            'CHAT: private chat with Ana - 2 messages, 2026-11-09 09:12 to '
            "2026-11-09 09:15 (the whole conversation). Times are the viewer's "
            'local time.\n'
            '[2026-11-09 09:12] ana: Shall we send the quote today?\n'
            '[2026-11-09 09:15] me (you): Yes, after lunch',
          ),
        );
        expect(question, isNot(contains('Shall we send')));
      },
    );

    test(
      'the name falls back to the username when there is no display name',
      () async {
        final r = Rig();
        final bare = AiRepositoryImpl(
          r.socket,
          FakeStore(),
          r.messages,
          displayNameOf: (_) => '  ',
          clock: () => DateTime(2026, 11, 11, 10),
        );
        r.socket.answers['assistant.relay'] = ok('x');
        await bare
            .summarize(
              const AiSummaryRequest(
                chatId: 'dm:ana',
                title: 'Ana',
                range: AiRange.everything,
                agent: claude,
              ),
            )
            .single;
        final payload = r.socket.calls.single.args['payload'] as Map;
        expect(
          payload['system'],
          startsWith('You are the friendly My Workspace assistant for me. '),
        );
      },
    );

    test('the answer keeps its chart blocks; a malformed one is empty', () async {
      final r = Rig();
      const text =
          'Sales rose.\n\n```chart\n{"type":"bar","data":[{"label":"a","value":1}]}\n```\n\n- Done';
      r.socket.answers['assistant.relay'] = ok(text);
      final chunk = await r.ask();
      expect(chunk.text, text);
      r.socket.answers['assistant.relay'] = ok('```chart\n{"type":"bar"}\n```');
      await expectLater(
        r.ask(),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.emptyAnswer),
        ),
      );
    });

    test('a date range puts the date in the question', () {
      expect(
        AiPrompt.question('Sales', isGroup: true, since: DateTime(2026, 11, 3)),
        startsWith(
          'Summarise my group chat "Sales", only the messages from '
          '2026-11-03 on. Give the main points,',
        ),
      );
    });

    test('the prompt text is the doc word for word', () {
      final doc = File(
        'reference/ai-chat/MOBILE_AI_IN_CHAT_FOLLOWUP.md',
      ).readAsStringSync();
      expect(doc, contains(AiPrompt.chatRules));
      expect(doc, contains(AiPrompt.styleGuide));
      expect(
        AiPrompt.chatRules,
        contains(
          '(never infer one). and if something is not in the transcript',
        ),
      );
      expect(AiPrompt.styleGuide, startsWith('Answer style (follow it'));
      expect(AiPrompt.styleGuide, endsWith('as short as the question allows.'));
      expect(AiPrompt.dateString(DateTime(2026, 11, 1)), 'Sun Nov 01 2026');
    });

    test('reads the text of a Gemini and an OpenAI body', () {
      expect(
        AiRelay.text('gemini', {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'a'},
                  {'text': 'b'},
                ],
              },
            },
          ],
        }),
        'ab',
      );
      expect(
        AiRelay.text('openai', {
          'choices': [
            {
              'message': {'content': 'hi'},
            },
          ],
        }),
        'hi',
      );
      expect(AiRelay.text('anthropic', {'content': []}), '');
    });

    test('builds each provider body: transcript in the system part', () {
      final anthropic = AiRelay.payload(claude, system: 'SYS', question: 'Q');
      expect(anthropic['system'], 'SYS');
      expect(anthropic['messages'], [
        {'role': 'user', 'content': 'Q'},
      ]);
      expect(anthropic['model'], 'claude-haiku-5-5');
      final gemini = AiRelay.payload(
        const AiAgent(id: 'g', name: 'G', provider: 'gemini'),
        system: 'SYS',
        question: 'Q',
      );
      expect(gemini['systemInstruction'], {
        'parts': [
          {'text': 'SYS'},
        ],
      });
      expect(gemini['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'Q'},
          ],
        },
      ]);
      expect(gemini['generationConfig'], {'temperature': 0});
      final openai = AiRelay.payload(
        const AiAgent(id: 'o', name: 'O', provider: 'openai', model: 'm'),
        system: 'SYS',
        question: 'Q',
      );
      expect(openai['messages'], [
        {'role': 'system', 'content': 'SYS'},
        {'role': 'user', 'content': 'Q'},
      ]);
      expect(openai['temperature'], 0);
    });

    test('an empty range makes no call', () async {
      final r = Rig();
      r.messages.rows = [];
      await expectLater(
        r.ask(),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.noMessages),
        ),
      );
      expect(r.socket.calls, isEmpty);
    });

    test('no agent makes no call', () async {
      final r = Rig();
      await expectLater(
        r.repo
            .summarize(
              const AiSummaryRequest(
                chatId: 'dm:ana',
                title: 'Ana',
                range: AiRange.everything,
              ),
            )
            .drain<void>(),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.notSetUp),
        ),
      );
      expect(r.socket.calls, isEmpty);
    });

    for (final (code, kind) in [
      ('no_agent', AiErrorKind.notSetUp),
      ('no_access', AiErrorKind.noPermission),
      ('not_found', AiErrorKind.agentGone),
      ('key_unreadable', AiErrorKind.keyUnreadable),
      ('rate_limited', AiErrorKind.rateLimited),
      ('too_large', AiErrorKind.tooLarge),
      ('upstream_timeout', AiErrorKind.timeout),
      ('upstream_unavailable', AiErrorKind.providerUnreachable),
      ('no_key', AiErrorKind.noKey),
      ('forbidden_address', AiErrorKind.forbiddenAddress),
      ('timeout', AiErrorKind.serverTimeout),
      ('test_timeout', AiErrorKind.serverTimeout),
      ('disconnected', AiErrorKind.offline),
      ('not_connected', AiErrorKind.offline),
      ('whatever', AiErrorKind.failed),
    ]) {
      test('server code $code is $kind', () async {
        final r = Rig();
        r.socket.answers['assistant.relay'] = SocketCallError(code);
        await expectLater(
          r.ask(),
          throwsA(isA<AiError>().having((e) => e.kind, 'kind', kind)),
        );
      });
    }

    test('rate_limited: per person and per agent by the server text', () async {
      for (final (text, kind) in [
        (
          'Too many questions in a minute. Try again shortly.',
          AiErrorKind.rateLimited,
        ),
        (
          'The AI is busy right now. Try again in a moment.',
          AiErrorKind.agentBusy,
        ),
        ('', AiErrorKind.rateLimited),
      ]) {
        final r = Rig();
        r.socket.answers['assistant.relay'] = SocketCallError(
          'rate_limited',
          text,
        );
        await expectLater(
          r.ask(),
          throwsA(isA<AiError>().having((e) => e.kind, 'kind', kind)),
        );
      }
    });

    for (final (status, body, kind) in <(int, Object?, AiErrorKind)>[
      (402, null, AiErrorKind.noCredit),
      (
        400,
        {
          'error': {'message': 'Your credit balance is too low'},
        },
        AiErrorKind.noCredit,
      ),
      (401, null, AiErrorKind.badKey),
      (403, null, AiErrorKind.badKey),
      (
        400,
        {
          'error': {'message': 'invalid x-api-key'},
        },
        AiErrorKind.badKey,
      ),
      (429, null, AiErrorKind.providerRateLimited),
      (404, null, AiErrorKind.modelUnavailable),
      (
        400,
        {
          'error': {'message': 'unknown model'},
        },
        AiErrorKind.modelUnavailable,
      ),
      (413, null, AiErrorKind.tooLarge),
      (503, null, AiErrorKind.providerBusy),
      (529, null, AiErrorKind.providerBusy),
      (
        400,
        {
          'error': {'message': 'bad shape'},
        },
        AiErrorKind.badRequest,
      ),
      (418, null, AiErrorKind.failed),
    ]) {
      test('provider $status is $kind', () async {
        final r = Rig();
        r.socket.answers['assistant.relay'] = {'status': status, 'body': body};
        await expectLater(
          r.ask(),
          throwsA(isA<AiError>().having((e) => e.kind, 'kind', kind)),
        );
      });
    }

    test('a 2xx answer without text is the empty answer', () async {
      final r = Rig();
      r.socket.answers['assistant.relay'] = ok('  ');
      await expectLater(
        r.ask(),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.emptyAnswer),
        ),
      );
    });

    test('a refused request keeps only the provider reason, cut to 160', () {
      final long = 'x' * 300;
      final e = AiRelay.fromProvider(400, {
        'error': {'message': long},
      });
      expect(e.kind, AiErrorKind.badRequest);
      expect(
        e.message,
        'The AI provider could not use that request: ${'x' * 160}',
      );
    });

    test('cancel drops a late answer', () async {
      final r = Rig();
      final gate = Completer<void>();
      r.socket.held['assistant.relay'] = gate.future;
      r.socket.answers['assistant.relay'] = ok('late');
      final events = <Object>[];
      final done = Completer<void>();
      r.repo
          .summarize(
            const AiSummaryRequest(
              chatId: 'dm:ana',
              title: 'Ana',
              range: AiRange.everything,
              agent: claude,
            ),
          )
          .listen(events.add, onError: events.add, onDone: done.complete);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      r.repo.cancel();
      gate.complete();
      await done.future;
      expect(events, isEmpty);
    });
  });

  group('transcript', () {
    String nameOf(String u) => u;

    test('header, lines, replies and the viewer marked', () {
      final t = AiTranscript.build(
        [
          msg(
            '1',
            'Shall we?',
            DateTime(2026, 11, 9, 9, 12).millisecondsSinceEpoch,
          ),
          Message(
            msgId: '2',
            convId: 'dm:ana',
            sender: 'me',
            isMine: true,
            text: 'Yes',
            ts: DateTime(2026, 11, 9, 9, 15).millisecondsSinceEpoch,
            status: MessageStatus.sent,
            replyTo: '1',
          ),
        ],
        kind: 'group',
        title: 'Sales',
        since: null,
        nameOf: nameOf,
      );
      expect(t.count, 2);
      expect(
        t.text,
        startsWith(
          'CHAT: group Sales - 2 messages, 2026-11-09 09:12 to 2026-11-09 09:15 (the whole conversation). Times are the viewer\'s local time.\n',
        ),
      );
      expect(
        t.text,
        contains(
          '[2026-11-09 09:15] me (you) (reply to ana: "Shall we?"): Yes',
        ),
      );
    });

    test('drops deleted and unreadable, applies since, cuts long texts', () {
      final day = DateTime(2026, 11, 9).millisecondsSinceEpoch;
      final t = AiTranscript.build(
        [
          msg('0', 'old', day - 1000),
          msg('1', 'a' * 900, day + 1000),
          msg('2', 'gone', day + 2000).copyWith(isDeleted: true),
        ],
        kind: 'dm',
        title: 'Ana',
        since: DateTime(2026, 11, 9),
        nameOf: nameOf,
      );
      expect(t.count, 1);
      expect(t.text, contains('1 message, '));
      expect(t.text, isNot(contains('old')));
      expect(t.text.split('\n').last.length, lessThan(700));
    });

    test('keeps the newest 300 and says so', () {
      final rows = [for (var i = 1; i <= 350; i++) msg('$i', 'm$i', i * 1000)];
      final t = AiTranscript.build(
        rows,
        kind: 'dm',
        title: 'Ana',
        since: null,
        nameOf: nameOf,
      );
      expect(t.count, 300);
      expect(
        t.text,
        contains(
          '(only the newest 300 of 350 are shown: older messages were not '
          "read). Times are the viewer's local time.",
        ),
      );
      expect(t.text, isNot(contains(': m50\n')));
    });

    test('stays under 60 000 characters', () {
      final rows = [
        for (var i = 1; i <= 300; i++) msg('$i', 'w' * 600, i * 1000),
      ];
      final t = AiTranscript.build(
        rows,
        kind: 'dm',
        title: 'Ana',
        since: null,
        nameOf: nameOf,
      );
      expect(t.text.length, lessThan(AiTranscript.maxChars + 400));
      expect(t.count, greaterThanOrEqualTo(AiTranscript.minLines));
    });

    test('the web example, character for character', () {
      final form = Message(
        msgId: '5',
        convId: 'group:reports',
        sender: 'ravi',
        isMine: false,
        kind: 'form',
        text: '',
        ts: DateTime(2026, 11, 9, 11, 40).millisecondsSinceEpoch,
        status: MessageStatus.sent,
        formJson:
            '{"caption":"Leave Request","submissionId":12,"structure":"leave",'
            '"fields":[{"name":"from","caption":"From","value":"2026-11-20"},'
            '{"name":"type","caption":"Leave type","value":"Casual Leave"},'
            '{"name":"note","caption":"Note","value":""}]}',
      );
      Message g(
        String id,
        String from,
        String text,
        int h,
        int m, {
        String? replyTo,
        bool isMine = false,
      }) => Message(
        msgId: id,
        convId: 'group:reports',
        sender: from,
        isMine: isMine,
        text: text,
        ts: DateTime(2026, 11, 9, h, m).millisecondsSinceEpoch,
        status: MessageStatus.sent,
        replyTo: replyTo,
      );
      final t = AiTranscript.build(
        [
          form,
          g(
            '1',
            'asha',
            'Can we ship the report on Friday?',
            10,
            2,
            isMine: true,
          ),
          g(
            '2',
            'ravi',
            'Friday works if finance sends the numbers today.',
            10,
            5,
            replyTo: '1',
          ),
          g(
            '3',
            'asha',
            "I'll chase finance. Will confirm by 3pm.",
            10,
            6,
            isMine: true,
          ),
          g('4', 'ravi', 'gone', 10, 7).copyWith(isDeleted: true),
          g('6', 'ravi', '   ', 10, 8),
        ],
        kind: 'group',
        title: 'Reports team',
        since: null,
        nameOf: nameOf,
        statusOf: (id) => id == '12' ? 'Approved' : null,
      );
      expect(
        t.text,
        'CHAT: group Reports team - 4 messages, 2026-11-09 10:02 to '
        "2026-11-09 11:40 (the whole conversation). Times are the viewer's "
        'local time.\n'
        '[2026-11-09 10:02] asha (you): Can we ship the report on Friday?\n'
        '[2026-11-09 10:05] ravi (reply to asha: "Can we ship the report on '
        'Friday?"): Friday works if finance sends the numbers today.\n'
        "[2026-11-09 10:06] asha (you): I'll chase finance. Will confirm by "
        '3pm.\n'
        '[2026-11-09 11:40] ravi: [form submission] Leave Request #12 '
        '(Approved) - From: 2026-11-20; Leave type: Casual Leave',
      );
    });

    test('empty chat, a nameless sender and kinds of chat', () {
      final empty = AiTranscript.build(
        [],
        kind: 'host',
        title: 'Ops',
        since: DateTime(2026, 11, 9),
        nameOf: nameOf,
      );
      expect(empty.isEmpty, isTrue);
      expect(empty.text, 'The host chat Ops has no messages since 2026-11-09.');
      final one = AiTranscript.build(
        [msg('1', 'hi', 1000).copyWith()],
        kind: 'global',
        title: 'Everyone',
        since: null,
        nameOf: (_) => ' ',
      );
      expect(one.text, contains('CHAT: chat Everyone - 1 message, '));
      expect(one.text, contains(': hi'));
      expect(one.text, contains('] someone: hi'));
    });
  });
}
