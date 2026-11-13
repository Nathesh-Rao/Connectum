import 'package:connectum/data/ai/ai_error_text.dart';
import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_prompt.dart';
import 'package:connectum/data/ai/ai_repository_impl.dart';
import 'package:connectum/data/ai/ai_transcript.dart';
import 'package:connectum/data/ai/fake_ai_repository.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/ai_chat/ai_texts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

final _now = DateTime(2026, 11, 12, 10);
const claude = AiAgent(id: 'claude', name: 'Claude', provider: 'anthropic');

Message _msg(int i, {String text = 'hello', String sender = 'ravi'}) => Message(
  msgId: 'id$i',
  convId: 'group:care-ravi',
  sender: sender,
  isMine: false,
  status: MessageStatus.sent,
  text: text,
  ts: DateTime(2026, 11, 1).millisecondsSinceEpoch + i * 60000,
);

/// The rows SQLite would hold for the care thread, and the history fetch.
class _Rows extends Fake implements MessageRepository {
  _Rows(this.rows, {this.hasMore = false, this.isReachable = true});

  final List<Message> rows;
  final bool hasMore;
  final bool isReachable;
  final fetched = <String>[];

  @override
  Future<bool?> fetchRecent(
    String convId, {
    required int atLeast,
    int maxPages = 10,
  }) async {
    fetched.add('$convId:$atLeast');
    return isReachable ? hasMore : null;
  }

  int settled = 0;

  @override
  Future<bool> hasEncryptedHistory(String convId) async => false;

  @override
  Future<void> settleDecrypt() async => settled++;

  @override
  Future<List<Message>> readFor(String org, String user, String convId) async =>
      rows;
}

class _Rig {
  _Rig({
    String user = 'me',
    List<Message>? rows,
    bool hasMore = false,
    bool isReachable = true,
  }) : messages = _Rows(
         rows ?? [_msg(1, text: 'Feeling better'), _msg(2, sender: 'nurse')],
         hasMore: hasMore,
         isReachable: isReachable,
       ) {
    socket.goOnline();
    socket.answers['care.thread'] = {
      'conversation': 'group:care-ravi',
      'person': 'ravi',
    };
    socket.answers['care.summary'] = {
      'person': {'name': 'Ravi Kumar', 'username': 'ravi'},
      'team': [
        {
          'username': 'nurse',
          'name': 'Nina Nurse',
          'role': 'Nurse',
          'roles': ['Nurse'],
        },
      ],
      'stats': {'forms': 1, 'messages': 1, 'truncated': false},
      'latest': [],
      'timeline': [],
    };
    socket.answers['assistant.relay'] = {
      'status': 200,
      'body': {
        'content': [
          {'type': 'text', 'text': 'An answer.'},
        ],
      },
    };
    repo = AiRepositoryImpl(
      socket,
      FakeStore(user: user),
      messages,
      displayNameOf: (u) => u == 'me' ? 'Maya Rao' : u,
      clock: () => _now,
    );
  }

  final socket = FakeSocket();
  final _Rows messages;
  late final AiRepositoryImpl repo;

  Future<AiSummaryChunk> ask({String? question, String person = 'ravi'}) => repo
      .summarize(
        AiSummaryRequest(
          chatId: 'group:care-$person',
          title: 'Ravi Kumar',
          range: AiRange.everything,
          agent: claude,
          carePerson: person,
          question: question,
        ),
      )
      .single;

  String get system =>
      (socket.calls.last.args['payload'] as Map)['system'] as String;
}

void main() {
  group('who is the patient', () {
    test('the signed-in username against the thread person, ignoring case', () {
      expect(AiPrompt.isPatient('ravi', 'ravi'), isTrue);
      expect(AiPrompt.isPatient('Ravi', 'ravi '), isTrue);
      expect(AiPrompt.isPatient('nurse', 'ravi'), isFalse);
      expect(AiPrompt.isPatient('', ''), isFalse);
    });

    test('the patient and the team get their own system text', () async {
      final patient = _Rig(user: 'ravi');
      final a = await patient.ask(question: 'What dose?');
      expect(
        patient.system,
        startsWith(
          AiPrompt.carePatientOpening(
            'Maya Rao',
            _now,
          ).replaceFirst('Maya Rao', 'ravi'),
        ),
      );
      expect(patient.system, contains('Never give a diagnosis'));
      expect(a.isPatientView, isTrue);

      final team = _Rig();
      final b = await team.ask(question: 'What dose?');
      expect(
        team.system,
        startsWith(
          "You answer questions about ONE patient's shared care thread for "
          'Maya Rao. Today is Thu Nov 12 2026.',
        ),
      );
      expect(team.system, isNot(contains('PATIENT themselves')));
      expect(b.isPatientView, isFalse);
    });

    test('both versions keep the shared rules verbatim', () async {
      for (final user in ['me', 'ravi']) {
        final r = _Rig(user: user);
        await r.ask(question: 'q');
        expect(r.system, contains(AiPrompt.careThreadIntro));
        expect(r.system, contains(AiPrompt.careNotRecorded));
        expect(r.system, contains('say it is not recorded there'));
        expect(
          r.system,
          contains('politely say you can only answer about this'),
        );
      }
    });
  });

  group('which call', () {
    test('the one-tap summary uses care.summary only', () async {
      final r = _Rig();
      await r.ask();
      expect(r.socket.count('care.summary'), 1);
      expect(r.socket.count('care.thread'), 0);
      expect(r.messages.fetched, isEmpty);
    });

    test(
      'a typed question uses care.thread, the history and the team',
      () async {
        final r = _Rig();
        final chunk = await r.ask(question: ' Who said that? ');
        expect(r.socket.count('care.thread'), 1);
        expect(r.socket.calls.first.args, {'person': 'ravi'});
        expect(r.messages.fetched, ['group:care-ravi:400']);
        expect(r.system, contains('TEAM\n- Nina Nurse (Nurse)'));
        expect(
          r.system,
          contains('THE GROUP CHAT, IN ORDER\nCHAT: group Ravi Kumar'),
        );
        expect(r.system, contains('Feeling better'));
        final payload = r.socket.calls.last.args['payload'] as Map;
        expect(jsonOf(payload), contains('Who said that?'));
        expect(chunk.messageCount, 2);
      },
    );

    test('a history that did not arrive is a server timeout', () async {
      final r = _Rig(isReachable: false);
      await expectLater(
        r.ask(question: 'q'),
        throwsA(
          isA<AiError>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.serverTimeout,
          ),
        ),
      );
      expect(r.socket.count('assistant.relay'), 0);
    });

    test('a thread with nothing in it is "nothing recorded"', () async {
      final r = _Rig(rows: const []);
      await expectLater(
        r.ask(question: 'q'),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.careEmpty),
        ),
      );
      expect(r.socket.count('assistant.relay'), 0);
    });

    test(
      'the patient gets the patient wording of "nothing recorded"',
      () async {
        final r = _Rig(user: 'ravi', rows: const []);
        await expectLater(
          r.ask(question: 'q'),
          throwsA(
            isA<AiError>().having(
              (e) => e.kind,
              'kind',
              AiErrorKind.careEmptyPatient,
            ),
          ),
        );
        expect(r.socket.count('assistant.relay'), 0);
      },
    );

    test('an EMPTY care.summary after the first employee joined is a friendly '
        'state, for the one-tap summary too', () async {
      for (final (user, kind) in [
        ('me', AiErrorKind.careEmpty),
        ('ravi', AiErrorKind.careEmptyPatient),
      ]) {
        final r = _Rig(user: user);
        r.socket.answers['care.summary'] = {
          'person': {'name': 'Ravi Kumar', 'username': 'ravi'},
          'team': [],
          'stats': {'forms': 0, 'messages': 0, 'truncated': false},
          'latest': [],
          'timeline': [],
        };
        await expectLater(
          r.ask(),
          throwsA(isA<AiError>().having((e) => e.kind, 'kind', kind)),
        );
        expect(r.socket.count('assistant.relay'), 0);
      }
    });

    test('the words: team and patient, no error title', () {
      expect(AiTexts.errorTitle(AiErrorKind.careEmpty), 'Nothing recorded yet');
      expect(
        AiTexts.errorTitle(AiErrorKind.careEmptyPatient),
        'Nothing recorded yet',
      );
      expect(
        AiTexts.errorText(AiErrorKind.careEmpty),
        contains('in this thread yet'),
      );
      expect(
        AiTexts.errorText(AiErrorKind.careEmptyPatient),
        contains('your care conversation'),
      );
    });

    test(
      'older messages the server still holds are said in the header',
      () async {
        final r = _Rig(hasMore: true);
        await r.ask(question: 'q');
        expect(r.system, contains('only the newest 2 are shown'));
      },
    );
  });

  group('trimming', () {
    test('400 messages: the oldest go first and the header says so', () {
      final rows = [for (var i = 0; i < 450; i++) _msg(i, text: 'm$i')];
      final t = AiTranscript.build(
        rows,
        kind: 'group',
        title: 'Ravi Kumar',
        since: null,
        nameOf: (u) => u,
        limitMessages: AiTranscript.careMaxMessages,
        limitChars: AiTranscript.careMaxChars - AiTranscript.headerReserve,
        keepLines: 1,
      );
      expect(t.count, 400);
      expect(t.text, contains('only the newest 400 of 450 are shown'));
      expect(t.text, isNot(contains(': m49\n')));
      expect(t.text, contains(': m50\n'));
      expect(t.text, endsWith(': m449'));
    });

    test('70,000 characters is never exceeded, header included', () {
      final rows = [for (var i = 0; i < 400; i++) _msg(i, text: 'x' * 590)];
      final t = AiTranscript.build(
        rows,
        kind: 'group',
        title: 'R' * AiTranscript.careTitleChars,
        since: null,
        nameOf: (u) => u,
        limitMessages: AiTranscript.careMaxMessages,
        limitChars: AiTranscript.careMaxChars - AiTranscript.headerReserve,
        keepLines: 1,
      );
      expect(t.text.length, lessThanOrEqualTo(AiTranscript.careMaxChars));
      expect(t.count, lessThan(400));
      expect(t.text, contains('older messages were not read'));
      expect(t.text, endsWith('x' * 590));
    });

    test('the canned long thread sits just under both limits', () async {
      final t = FakeAiRepository(delay: Duration.zero)
        ..care = FakeCareThread.long;
      final thread = await t.careThread('ravi');
      expect(thread.count, 400);
      expect(thread.transcript.length, lessThanOrEqualTo(70000));
      expect(thread.transcript.length, greaterThan(65000));
    });
  });

  group('not_found', () {
    test('is matched by code, whatever the server says', () async {
      for (final text in ['No such user.', 'Reworded: nobody here.', '']) {
        final r = _Rig();
        r.socket.answers['care.thread'] = SocketCallError('not_found', text);
        await expectLater(
          r.ask(question: 'q'),
          throwsA(
            isA<AiError>()
                .having((e) => e.kind, 'kind', AiErrorKind.careNotFound)
                .having((e) => e.message, 'message', isNull),
          ),
        );
        expect(r.socket.count('assistant.relay'), 0);
      }
    });

    test(
      'the text alone never decides: another code is not not_found',
      () async {
        final r = _Rig();
        r.socket.answers['care.thread'] = const SocketCallError(
          'invalid',
          'No such user.',
        );
        await expectLater(
          r.ask(question: 'q'),
          throwsA(
            isA<AiError>().having(
              (e) => e.kind,
              'kind',
              isNot(AiErrorKind.careNotFound),
            ),
          ),
        );
      },
    );

    test(
      'the patient gets the "starts once your care team is connected" words',
      () async {
        final r = _Rig(user: 'ravi');
        r.socket.answers['care.thread'] = const SocketCallError(
          'not_found',
          'x',
        );
        await expectLater(
          r.ask(question: 'q'),
          throwsA(
            isA<AiError>().having(
              (e) => e.kind,
              'kind',
              AiErrorKind.careNotStarted,
            ),
          ),
        );
        final s = _Rig(user: 'ravi');
        s.socket.answers['care.summary'] = const SocketCallError(
          'not_found',
          'x',
        );
        await expectLater(
          s.ask(),
          throwsA(
            isA<AiError>().having(
              (e) => e.kind,
              'kind',
              AiErrorKind.careNotStarted,
            ),
          ),
        );
      },
    );

    test('the words', () {
      expect(
        AiErrorText.classifyCareError('timeout', isPatient: false),
        isNull,
      );
      expect(
        AiTexts.errorText(AiErrorKind.careNotStarted, detail: 'server text'),
        contains('starts once your care team is connected'),
      );
      expect(
        AiTexts.errorText(AiErrorKind.careNotFound, detail: 'server text'),
        'There is no shared care conversation with this person yet.',
      );
    });
  });

  group('other chats and e2e', () {
    test('a plain chat is unchanged: no care calls', () async {
      final r = _Rig();
      final chunk = await r.repo
          .summarize(
            const AiSummaryRequest(
              chatId: 'group:team',
              title: 'Team',
              range: AiRange.everything,
              agent: claude,
            ),
          )
          .single;
      expect(chunk.isPatientView, isFalse);
      expect(r.socket.count('care.thread'), 0);
      expect(r.socket.count('care.summary'), 0);
      expect(r.system, contains('CHAT IN FOCUS'));
      expect(r.system, isNot(contains('TEAM\n')));
    });
  });

  group('FakeAiRepository care cases', () {
    test('team, patient, long and not_found', () async {
      final f = FakeAiRepository(delay: Duration.zero);
      final team = await f.careThread('ravi');
      expect(team.isPatient, isFalse);
      expect(team.team, isNotEmpty);
      expect(f.careSystemFor(team, _now), contains('ONE patient'));

      f.care = FakeCareThread.patient;
      final patient = await f.careThread('ravi');
      expect(patient.isPatient, isTrue);
      expect(f.careSystemFor(patient, _now), contains('PATIENT themselves'));

      f.care = FakeCareThread.notFound;
      await expectLater(
        f.careThread('ravi'),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'k', AiErrorKind.careNotFound),
        ),
      );
      f.care = FakeCareThread.patientNotFound;
      await expectLater(
        f.careThread('ravi'),
        throwsA(
          isA<AiError>().having((e) => e.kind, 'k', AiErrorKind.careNotStarted),
        ),
      );
    });

    test('empty and patientEmpty give an empty thread', () async {
      final f = FakeAiRepository(delay: Duration.zero)
        ..care = FakeCareThread.empty;
      expect((await f.careThread('ravi')).count, 0);
      const request = AiSummaryRequest(
        chatId: 'group:care-ravi',
        title: 'Ravi',
        range: AiRange.everything,
        carePerson: 'ravi',
      );
      await expectLater(
        f.summarize(request).single,
        throwsA(
          isA<AiError>().having((e) => e.kind, 'k', AiErrorKind.careEmpty),
        ),
      );
      f.care = FakeCareThread.patientEmpty;
      await expectLater(
        f.summarize(request).single,
        throwsA(
          isA<AiError>().having(
            (e) => e.kind,
            'k',
            AiErrorKind.careEmptyPatient,
          ),
        ),
      );
    });

    test('a typed question answers or fails like the real one', () async {
      final f = FakeAiRepository(delay: Duration.zero)
        ..care = FakeCareThread.patient;
      const request = AiSummaryRequest(
        chatId: 'group:care-ravi',
        title: 'Ravi',
        range: AiRange.everything,
        carePerson: 'ravi',
        question: 'What dose?',
      );
      final chunk = await f.summarize(request).single;
      expect(chunk.isPatientView, isTrue);
      f.care = FakeCareThread.notFound;
      await expectLater(f.summarize(request).single, throwsA(isA<AiError>()));
    });
  });
}

String jsonOf(Map payload) => payload.toString();
