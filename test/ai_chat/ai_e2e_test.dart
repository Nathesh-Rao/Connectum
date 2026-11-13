import 'dart:async';

import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_repository_impl.dart';
import 'package:connectum/data/ai/ai_setup_cache.dart';
import 'package:connectum/data/ai/ai_transcript.dart';
import 'package:connectum/data/ai/fake_ai_repository.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/features/ai_chat/ai_entry.dart';
import 'package:connectum/features/ai_chat/ai_summary_controller.dart';
import 'package:connectum/features/ai_chat/ai_texts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

// AI is BLOCKED in end-to-end chats on mobile (the BE decision is unchanged,
// 13 Nov 2026): no decrypting for AI, and no plaintext of an encrypted chat
// ever reaches assistant.relay or a prompt.

const _envelope = 'e2e1:SECRETCIPHERTEXT';
const _secret = 'The launch code is 4711';
const claude = AiAgent(id: 'claude', name: 'Claude', provider: 'anthropic');
final _day = DateTime(2026, 11, 9, 9).millisecondsSinceEpoch;

/// An end-to-end row as SQLite holds it: [text] is the opened text when
/// [state] is ok, else the envelope.
Message _e2e(int i, String plain, {String state = 'ok', bool isMine = false}) =>
    Message(
      msgId: 'm$i',
      convId: 'dm:ana',
      sender: isMine ? 'me' : 'ana',
      isMine: isMine,
      text: state == 'ok' ? plain : _envelope,
      ts: _day + i * 60000,
      status: MessageStatus.sent,
      isEncrypted: true,
      decryptState: state,
    );

Message _plain(int i, String text) => Message(
  msgId: 'p$i',
  convId: 'dm:ana',
  sender: 'ana',
  isMine: false,
  text: text,
  ts: _day + i * 60000,
  status: MessageStatus.sent,
);

/// The message store: [flagged] is the chat's encrypted flag, [rows] what
/// SQLite holds. Every call is logged so a test can prove nothing was read.
class _Rows extends Fake implements MessageRepository {
  _Rows(this.rows, {this.flagged = true});

  final List<Message> rows;
  final bool flagged;
  final calls = <String>[];

  @override
  Future<bool> hasEncryptedHistory(String convId) async => flagged;

  @override
  Future<void> settleDecrypt() async => calls.add('settle');

  @override
  Future<bool?> fetchRecent(
    String convId, {
    required int atLeast,
    int maxPages = 10,
  }) async {
    calls.add('fetch');
    return false;
  }

  @override
  Future<List<Message>> readFor(String org, String user, String convId) async {
    calls.add('read');
    return rows;
  }
}

class _Rig {
  _Rig(List<Message> rows, {bool flagged = true})
    : messages = _Rows(rows, flagged: flagged) {
    socket.goOnline();
    socket.answers['assistant.relay'] = {
      'status': 200,
      'body': {
        'content': [
          {'type': 'text', 'text': 'An answer.'},
        ],
      },
    };
    socket.answers['care.thread'] = {
      'conversation': 'group:care-ravi',
      'person': 'ravi',
    };
    socket.answers['care.summary'] = {
      'person': {'name': 'Ravi', 'username': 'ravi'},
      'team': [],
      'stats': {'forms': 1, 'messages': 1, 'truncated': false},
      'latest': [],
      'timeline': [],
    };
    repo = AiRepositoryImpl(
      socket,
      FakeStore(),
      messages,
      clock: () => DateTime(2026, 11, 11, 10),
    );
  }

  final socket = FakeSocket();
  final _Rows messages;
  late final AiRepositoryImpl repo;

  Future<AiSummaryChunk> ask(
    String chatId, {
    String? person,
    String? question,
  }) => repo
      .summarize(
        AiSummaryRequest(
          chatId: chatId,
          title: 'Ana',
          range: AiRange.everything,
          agent: claude,
          carePerson: person,
          question: question,
        ),
      )
      .single;

  void expectUntouched() {
    expect(socket.count('assistant.relay'), 0);
    expect(socket.count('care.summary'), 0);
    expect(socket.count('care.thread'), 0);
    expect(messages.calls, isEmpty, reason: 'nothing is read for AI');
  }
}

Matcher _blocked() => throwsA(
  isA<AiError>().having((e) => e.kind, 'kind', AiErrorKind.encrypted),
);

class _Entry {
  _Entry({this.isEncrypted = true})
    : fake = FakeAiRepository(delay: const Duration(milliseconds: 10)) {
    c = AiSummaryController(
      ai: fake,
      setup: AiSetupCache(fake),
      chatId: 'dm:ana',
      title: () => 'Ana',
      isEncrypted: () => isEncrypted,
      isOnline: () => true,
      post: (_) async => SendResult.queued,
      isAdmin: () => false,
    );
  }

  final FakeAiRepository fake;
  late final AiSummaryController c;
  bool isEncrypted;
}

void main() {
  group('the repository refuses an encrypted chat', () {
    test(
      'a summary of a flagged DM builds nothing and calls nothing',
      () async {
        final r = _Rig([_e2e(0, _secret)]);
        await expectLater(r.ask('dm:ana'), _blocked());
        r.expectUntouched();
      },
    );

    test('a flagged group is refused the same way', () async {
      final r = _Rig([_e2e(0, _secret)]);
      await expectLater(r.ask('group:team'), _blocked());
      r.expectUntouched();
    });

    test(
      'the care thread of a flagged chat: no care.* call, no relay',
      () async {
        final r = _Rig([_e2e(0, _secret)]);
        await expectLater(
          r.ask('group:care-ravi', person: 'ravi', question: 'What happened?'),
          _blocked(),
        );
        await expectLater(r.ask('group:care-ravi', person: 'ravi'), _blocked());
        r.expectUntouched();
      },
    );

    test('a care.thread whose conversation turns out encrypted stops '
        'before the history is fetched', () async {
      final r = _Rig([_e2e(0, _secret)]);
      await expectLater(r.repo.careThread('ravi'), _blocked());
      expect(r.messages.calls, isNot(contains('fetch')));
      expect(r.messages.calls, isNot(contains('read')));
      expect(r.socket.count('assistant.relay'), 0);
    });

    test(
      'even if the flag is missing, an encrypted row is never sent',
      () async {
        final r = _Rig([
          _e2e(0, _secret),
          _plain(1, 'plain hello'),
        ], flagged: false);
        await expectLater(r.ask('dm:ana'), _blocked());
        expect(r.socket.count('assistant.relay'), 0);
        expect(r.messages.calls, isNot(contains('settle')));
      },
    );

    test(
      'a normal chat is unchanged and does not wait for decrypting',
      () async {
        final r = _Rig([_plain(0, 'plain hello')], flagged: false);
        final chunk = await r.ask('dm:ana');
        expect(chunk.text, 'An answer.');
        final payload = r.socket.calls.single.args['payload'] as Map;
        expect(payload['system'], contains('plain hello'));
        expect(r.messages.calls, ['read']);
      },
    );

    test('nothing is logged', () async {
      final logged = <String>[];
      final old = debugPrint;
      debugPrint = (m, {wrapWidth}) => logged.add(m ?? '');
      try {
        await runZoned(
          () async {
            final r = _Rig([_e2e(0, _secret)]);
            await expectLater(r.ask('dm:ana'), _blocked());
          },
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => logged.add(line),
          ),
        );
      } finally {
        debugPrint = old;
      }
      expect(logged, isEmpty);
    });
  });

  group('the transcript drops every encrypted message', () {
    AiTranscript build(List<Message> rows) => AiTranscript.build(
      rows,
      kind: 'dm',
      title: 'Ana',
      since: null,
      nameOf: (u) => u,
    );

    test('opened, unreadable and still-opening rows never enter', () {
      final t = build([
        _plain(0, 'plain hello'),
        _e2e(1, _secret),
        _e2e(2, '', state: 'cant_decrypt'),
        _e2e(3, '', state: 'pending'),
      ]);
      expect(t.count, 1);
      expect(t.text, contains('plain hello'));
      expect(t.text, isNot(contains(_secret)));
      expect(t.text, isNot(contains(_envelope)));
      expect(t.text, isNot(contains('🔒')));
    });

    test('a chat of only encrypted rows is "no messages"', () {
      final t = build([_e2e(0, _secret)]);
      expect(t.isEmpty, isTrue);
      expect(t.text, isNot(contains(_secret)));
    });

    test('a reply quote never carries an encrypted parent', () {
      final reply = Message(
        msgId: 'r1',
        convId: 'dm:ana',
        sender: 'me',
        isMine: true,
        text: 'ok',
        ts: _day + 9 * 60000,
        status: MessageStatus.sent,
        replyTo: 'm0',
      );
      final t = build([_e2e(0, _secret), reply]);
      expect(t.text, isNot(contains(_secret)));
    });
  });

  group('every entry point of the controller is blocked', () {
    test('the header icon leads to the notice, with no call', () async {
      final r = _Entry();
      expect(await r.c.resolveEntry(), AiEntry.encrypted);
      await r.c.onSheetOpened();
      expect(r.fake.setupCalls, 0);
      expect(r.fake.summarizeCalls, 0);
      expect(AiTexts.encryptedTitle, 'AI not available in encrypted chats');
    });

    test('the summary option is refused', () async {
      final r = _Entry();
      expect(await r.c.summarize(), AiSummarizeResult.blocked);
      expect(r.fake.summarizeCalls, 0);
      expect(r.c.phase.value, AiPhase.menu);
    });

    test('a typed question and a retry are refused', () async {
      final r = _Entry();
      expect(await r.c.ask('What happened?'), AiSummarizeResult.blocked);
      expect(await r.c.retry(), AiSummarizeResult.blocked);
      expect(r.fake.summarizeCalls, 0);
      expect(r.fake.careThreadCalls, 0);
    });

    test('a care thread controller is refused too', () async {
      final fake = FakeAiRepository(delay: Duration.zero);
      final c = AiSummaryController(
        ai: fake,
        setup: AiSetupCache(fake),
        chatId: 'group:care-ravi',
        title: () => 'Ravi',
        isEncrypted: () => true,
        isOnline: () => true,
        post: (_) async => SendResult.queued,
        isAdmin: () => false,
        carePerson: 'ravi',
      );
      expect(await c.ask('Who?'), AiSummarizeResult.blocked);
      expect(await c.summarize(), AiSummarizeResult.blocked);
      expect(fake.summarizeCalls, 0);
      expect(fake.careThreadCalls, 0);
    });

    test(
      'every try is refused, also after the chat became encrypted',
      () async {
        final r = _Entry(isEncrypted: false);
        expect(await r.c.summarize(), AiSummarizeResult.started);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        r.isEncrypted = true;
        expect(await r.c.summarize(), AiSummarizeResult.blocked);
        expect(r.fake.summarizeCalls, 1);
      },
    );

    test('share posts nothing once the chat is encrypted', () async {
      final posted = <String>[];
      final fake = FakeAiRepository(delay: const Duration(milliseconds: 10));
      var isEncrypted = false;
      final c = AiSummaryController(
        ai: fake,
        setup: AiSetupCache(fake),
        chatId: 'dm:ana',
        title: () => 'Ana',
        isEncrypted: () => isEncrypted,
        isOnline: () => true,
        post: (t) async {
          posted.add(t);
          return SendResult.queued;
        },
        isAdmin: () => false,
      );
      await c.onSheetOpened();
      await c.summarize();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.canShare, isTrue);
      isEncrypted = true;
      expect(c.canShare, isFalse);
      expect(await c.share(), isFalse);
      expect(posted, isEmpty);
    });
  });

  testWidgets('the icon on an encrypted chat shows the notice, not the sheet', (
    tester,
  ) async {
    final r = _Entry();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openAi(context, r.c),
              child: const Text('ai'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ai'));
    await tester.pumpAndSettle();
    expect(find.text(AiTexts.encryptedTitle), findsOneWidget);
    expect(find.text(AiTexts.summarize), findsNothing);
    expect(r.fake.setupCalls, 0);
    expect(r.fake.summarizeCalls, 0);
  });
}
