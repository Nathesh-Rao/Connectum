import 'dart:async';

import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_prompt.dart';
import 'package:connectum/data/ai/ai_repository_impl.dart';
import 'package:connectum/data/ai/ai_setup_cache.dart';
import 'package:connectum/data/ai/care_summary_text.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/ai_chat/ai_summary_controller.dart';
import 'package:connectum/features/ai_chat/ai_texts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

final _now = DateTime(2026, 11, 11, 10);
int _ts(int d, int h, int m) =>
    DateTime(2026, 11, d, h, m).millisecondsSinceEpoch;

Map<String, dynamic> fixture() => {
  'person': {
    'name': 'Ravi Kumar',
    'username': 'ravi',
    'rows': [
      {'label': 'Age', 'value': '41'},
      {'label': 'Gender', 'value': 'Male'},
      {'label': 'Mobile', 'value': '9990001111'},
      {'label': 'City', 'value': 'Trichy'},
    ],
  },
  'team': [
    {
      'username': 'nurse',
      'name': 'Nina Nurse',
      'role': 'Nurse',
      'roles': ['Nurse', 'Lead'],
      'isEmployee': true,
      'entries': 2,
    },
    {
      'username': 'doc',
      'name': 'Dr Dev',
      'role': null,
      'roles': [],
      'isEmployee': true,
      'entries': 1,
    },
  ],
  'stats': {
    'forms': 2,
    'messages': 2,
    'people': 3,
    'first': _ts(9, 9, 12),
    'last': _ts(11, 8, 0),
    'truncated': true,
  },
  'latest': [
    {
      'structure': 'prescription',
      'caption': 'Prescription',
      'count': 2,
      'id': 7,
      'ts': _ts(10, 14, 5),
      'by': 'doc',
      'fields': [],
      'more': 0,
    },
    {
      'structure': 'vitals',
      'caption': 'Vitals',
      'count': 1,
      'id': 5,
      'ts': _ts(9, 9, 12),
      'by': 'nurse',
      'fields': [
        {'caption': 'BP', 'value': '120/80'},
        {'caption': 'Pulse', 'value': '72'},
      ],
      'more': 3,
    },
  ],
  'timeline': [
    {
      'id': 5,
      'ts': _ts(9, 9, 12),
      'kind': 'form',
      'by': 'nurse',
      'caption': 'Vitals',
      'structure': 'vitals',
      'fields': [
        {'caption': 'BP', 'value': '120/80'},
        {'caption': 'Pulse', 'value': '72'},
      ],
      'more': 3,
      'edited': true,
    },
    {
      'id': 6,
      'ts': _ts(9, 9, 30),
      'kind': 'chat',
      'by': 'ravi',
      'text': 'Feeling better',
      'edited': false,
    },
    {
      'id': 7,
      'ts': _ts(10, 14, 5),
      'kind': 'form',
      'by': 'doc',
      'caption': 'Prescription',
      'structure': 'prescription',
      'fields': [],
      'more': 0,
      'edited': false,
    },
    {
      'id': 8,
      'ts': _ts(11, 8, 0),
      'kind': 'chat',
      'by': 'nurse',
      'text': 'Come at 9',
      'edited': false,
    },
  ],
};

const expectedText = '''Ravi Kumar, 41 · Male · Trichy
2 forms and 2 messages by 3 people, 9 Nov to Today.
Team: Nina Nurse (Nurse, Lead), Dr Dev

Where things stand
- Prescription x2 - Yesterday 14:05, Dr Dev
- Vitals - 9 Nov 09:12, Nina Nurse (Nurse, Lead): BP: 120/80; Pulse: 72 (+3 more)

Timeline
9 Nov
  09:12 Vitals (edited) - Nina Nurse (Nurse, Lead): BP: 120/80; Pulse: 72 (+3 more)
  09:30 Ravi Kumar: Feeling better
Yesterday
  14:05 Prescription - Dr Dev
Today
  08:00 Nina Nurse (Nurse, Lead): Come at 9

Only the most recent entries are included.''';

class _NoMessages extends Fake implements MessageRepository {
  @override
  Future<List<Message>> readFor(String org, String user, String convId) =>
      throw StateError('a care summary reads no local messages');
}

Map<String, dynamic> ok(String text) => {
  'status': 200,
  'body': {
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
};

const claude = AiAgent(id: 'claude', name: 'Claude', provider: 'anthropic');

class Rig {
  Rig({String user = 'me'}) {
    socket.goOnline();
    socket.answers['care.summary'] = fixture();
    socket.answers['assistant.relay'] = ok('A fine summary.');
    socket.answers['ai.agents'] = {
      'agents': [
        {'id': 'claude', 'name': 'Claude', 'provider': 'anthropic'},
      ],
    };
    repo = AiRepositoryImpl(
      socket,
      FakeStore(user: user),
      _NoMessages(),
      displayNameOf: (u) => u == 'me' ? 'Maya Rao' : u,
      clock: () => _now,
    );
  }

  final socket = FakeSocket();
  late final AiRepositoryImpl repo;

  Future<AiSummaryChunk> ask({String person = 'ravi'}) => repo
      .summarize(
        AiSummaryRequest(
          chatId: 'group:care-$person',
          title: 'Ravi Kumar',
          range: AiRange.everything,
          agent: claude,
          carePerson: person,
        ),
      )
      .single;

  AiSummaryController controller({
    String person = 'ravi',
    List<String>? posted,
  }) => AiSummaryController(
    ai: repo,
    setup: AiSetupCache(repo),
    chatId: 'group:care-$person',
    title: () => 'Ravi Kumar',
    isOnline: () => true,
    post: (t) async {
      posted?.add(t);
      return SendResult.queued;
    },
    isAdmin: () => false,
    carePerson: person,
  );
}

void main() {
  group('the converter', () {
    test('turns a full response into the web text', () {
      expect(CareSummaryText.toPlainText(fixture(), now: _now), expectedText);
    });

    test('empty rows, no team, nothing recorded', () {
      final text = CareSummaryText.toPlainText({
        'person': {'name': 'Ana', 'username': 'ana', 'rows': []},
        'team': [],
        'stats': {
          'forms': 0,
          'messages': 0,
          'people': 0,
          'first': null,
          'last': null,
          'truncated': false,
        },
        'latest': [],
        'timeline': [],
      }, now: _now);
      expect(text, 'Ana\nNothing has been recorded in this thread yet.');
    });

    test('null first and last, no truncation note, one form', () {
      final text = CareSummaryText.toPlainText({
        'person': {'name': 'Ana', 'username': 'ana', 'rows': []},
        'team': [],
        'stats': {
          'forms': 1,
          'messages': 0,
          'people': 1,
          'first': null,
          'last': null,
          'truncated': false,
        },
        'latest': [],
        'timeline': [],
      }, now: _now);
      expect(text, 'Ana\n1 form by 1 person.');
    });

    test('only the facts that are present, and dates of another year', () {
      final text = CareSummaryText.toPlainText({
        'person': {
          'name': 'Ana',
          'username': 'ana',
          'rows': [
            {'label': 'City', 'value': 'Goa'},
            {'label': 'Email', 'value': 'a@b.c'},
          ],
        },
        'stats': {
          'forms': 0,
          'messages': 1,
          'people': 1,
          'first': DateTime(2025, 3, 2, 9).millisecondsSinceEpoch,
          'last': DateTime(2025, 3, 2, 9).millisecondsSinceEpoch,
        },
        'timeline': [
          {
            'ts': DateTime(2025, 3, 2, 9).millisecondsSinceEpoch,
            'kind': 'chat',
            'by': 'ana',
            'text': 'Hi',
          },
        ],
      }, now: _now);
      expect(text.split('\n').first, 'Ana, Goa');
      expect(text, contains('1 message by 1 person, 2 Mar 2025.'));
      expect(text, contains('Timeline\n2 Mar 2025\n  09:00 Ana: Hi'));
    });
  });

  group('the person of a care thread', () {
    test('comes from the group name', () {
      expect(CareSummaryText.personOf('group:care-ravi'), 'ravi');
      expect(CareSummaryText.personOf('group:care-ravi.k_2'), 'ravi.k_2');
      expect(CareSummaryText.personOf('group:care-'), isNull);
      expect(CareSummaryText.personOf('group:care-a b'), isNull);
      expect(CareSummaryText.personOf('group:sales'), isNull);
      expect(CareSummaryText.personOf('dm:care-ravi'), isNull);
    });

    test('the icon shows for a care thread with a person, not without', () {
      expect(aiAvailableIn('group:care-ravi'), isTrue);
      expect(aiAvailableIn('group:care-'), isFalse);
      for (final id in ['dm:ana', 'group:sales', 'host:support', 'global']) {
        expect(aiAvailableIn(id), isTrue, reason: id);
      }
      expect(aiAvailableIn('workspace:me'), isFalse);
    });
  });

  group('the flow', () {
    test('asks care.summary, then relays the converted text', () async {
      final r = Rig();
      final chunk = await r.ask();
      expect(r.socket.calls.map((c) => c.action), [
        'care.summary',
        'assistant.relay',
      ]);
      expect(r.socket.calls.first.args, {'person': 'ravi'});
      expect(chunk.text, 'A fine summary.');
      expect(chunk.messageCount, 2);
      expect(chunk.isTruncated, isTrue);
      final payload = r.socket.calls.last.args['payload'] as Map;
      final system = payload['system'] as String;
      expect(
        system,
        startsWith(
          "You answer questions about ONE patient's shared care thread for Maya Rao. Today is Wed Nov 11 2026.\n\n",
        ),
      );
      expect(system, contains('Be brief and direct: lead with the answer'));
      expect(system, contains('Answer style (follow it in every answer):'));
      expect(
        system,
        endsWith('THE THREAD, FORMS AND GROUP CHAT IN ORDER\n$expectedText'),
      );
      expect(
        (payload['messages'] as List).single['content'],
        AiPrompt.careQuestion('Ravi Kumar'),
      );
    });

    test(
      'the person asking about their own thread gets the patient wording',
      () async {
        final r = Rig(user: 'ravi');
        await r.ask();
        final system =
            (r.socket.calls.last.args['payload'] as Map)['system'] as String;
        expect(
          system,
          startsWith(
            'You answer questions about the care thread of ravi for the PATIENT themselves, in simple, kind, plain words',
          ),
        );
        expect(system, contains('Never give a diagnosis, treatment change'));
      },
    );

    test('not_found is matched by code and shows our words', () async {
      for (final text in [
        'No such user.',
        'No shared conversation with that person.',
      ]) {
        final r = Rig();
        r.socket.answers['care.summary'] = SocketCallError('not_found', text);
        await expectLater(
          r.ask(),
          throwsA(
            isA<AiError>()
                .having((e) => e.kind, 'kind', AiErrorKind.careNotFound)
                .having((e) => e.message, 'message', isNull),
          ),
        );
        expect(r.socket.count('assistant.relay'), 0);
        expect(
          AiTexts.errorText(AiErrorKind.careNotFound, detail: text),
          'There is no shared care conversation with this person yet.',
        );
      }
    });

    test('other errors go through the same handling as a chat', () async {
      final r = Rig();
      r.socket.answers['care.summary'] = const SocketCallError('timeout');
      await expectLater(
        r.ask(),
        throwsA(
          isA<AiError>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.serverTimeout,
          ),
        ),
      );
      final r2 = Rig();
      r2.socket.answers['assistant.relay'] = {'status': 402, 'body': null};
      await expectLater(
        r2.ask(),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.noCredit),
        ),
      );
    });

    test('a thread with nothing recorded says so and asks no AI', () async {
      final r = Rig();
      r.socket.answers['care.summary'] = {
        'person': {'name': 'Ana', 'username': 'ana', 'rows': []},
        'stats': {
          'forms': 0,
          'messages': 0,
          'people': 0,
          'first': null,
          'last': null,
        },
        'team': [],
        'latest': [],
        'timeline': [],
      };
      await expectLater(
        r.ask(),
        throwsA(
          isA<AiError>()
              .having((e) => e.kind, 'kind', AiErrorKind.noMessages)
              .having(
                (e) => e.message,
                'message',
                'Nothing has been recorded in this thread yet.',
              ),
        ),
      );
      expect(r.socket.count('assistant.relay'), 0);
    });

    test('the controller summarises a care thread without a range', () async {
      final posted = <String>[];
      final r = Rig();
      final c = r.controller(posted: posted);
      expect(c.isCare, isTrue);
      expect(c.canSummarize, isFalse);
      await c.onSheetOpened();
      expect(c.canSummarize, isTrue);
      await c.summarize();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.phase.value, AiPhase.result);
      expect(c.text.value, 'A fine summary.');
      expect(c.usedLabel.value, 'Whole thread');
      expect(c.isTruncated.value, isTrue);
      expect(c.sharePreview, '✨ AI summary\n\nA fine summary.');
      expect(await c.share(), isTrue);
      expect(posted.single, '✨ AI summary\n\nA fine summary.');
    });

    test(
      'the controller shows not_found with our words, not the server text',
      () async {
        final r = Rig();
        r.socket.answers['care.summary'] = const SocketCallError(
          'not_found',
          'No such user.',
        );
        final c = r.controller();
        await c.onSheetOpened();
        await c.summarize();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(c.phase.value, AiPhase.error);
        expect(c.error.value, AiErrorKind.careNotFound);
        expect(
          c.errorText(c.error.value!, c.errorDetail),
          'There is no shared care conversation with this person yet.',
        );
      },
    );

    test('a chat controller has no care person', () {
      final r = Rig();
      final c = AiSummaryController(
        ai: r.repo,
        setup: AiSetupCache(r.repo),
        chatId: 'dm:ana',
        title: () => 'Ana',
        isOnline: () => true,
        post: (_) async => SendResult.queued,
        isAdmin: () => false,
      );
      expect(c.isCare, isFalse);
      expect(c.canSummarize, isFalse);
    });

    test('no content is logged', () async {
      final logged = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logged.add(m ?? '');
      try {
        await runZoned(
          () async {
            final r = Rig();
            final c = r.controller();
            await c.onSheetOpened();
            await c.summarize();
            await Future<void>.delayed(const Duration(milliseconds: 50));
            r.socket.answers['care.summary'] = const SocketCallError(
              'not_found',
              'No such user.',
            );
            await c.summarize();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => logged.add(line),
          ),
        );
      } finally {
        debugPrint = old;
      }
      final all = logged.join('\n');
      for (final secret in [
        'Feeling better',
        'Ravi Kumar',
        '120/80',
        'A fine summary',
      ]) {
        expect(all, isNot(contains(secret)));
      }
    });
  });
}
