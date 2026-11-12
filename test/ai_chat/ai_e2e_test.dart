import 'dart:async';

import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_repository_impl.dart';
import 'package:connectum/data/ai/ai_transcript.dart';
import 'package:connectum/data/e2e/e2e_texts.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

const _envelope = 'e2e1:SECRETCIPHERTEXT';
const claude = AiAgent(id: 'claude', name: 'Claude', provider: 'anthropic');
final _day = DateTime(2026, 11, 9, 9).millisecondsSinceEpoch;

/// An end-to-end row as SQLite holds it: [text] is the opened text when
/// [state] is ok, else the envelope.
Message _e2e(
  int i,
  String plain, {
  String state = 'ok',
  String? code,
  bool isMine = false,
  String? replyTo,
}) => Message(
  msgId: 'm$i',
  convId: 'dm:ana',
  sender: isMine ? 'me' : 'ana',
  isMine: isMine,
  text: state == 'ok' ? plain : _envelope,
  ts: _day + i * 60000,
  status: MessageStatus.sent,
  isEncrypted: true,
  decryptState: state,
  unreadableCode: code,
  replyTo: replyTo,
);

class _Rows extends Fake implements MessageRepository {
  _Rows(this.rows);
  final List<Message> rows;
  final order = <String>[];

  @override
  Future<void> settleDecrypt() async => order.add('settle');

  @override
  Future<List<Message>> readFor(String org, String user, String convId) async {
    order.add('read');
    return rows;
  }
}

AiTranscript _build(List<Message> rows) => AiTranscript.build(
  rows,
  kind: 'dm',
  title: 'Ana',
  since: null,
  nameOf: (u) => u,
);

void main() {
  group('transcript of an end-to-end chat', () {
    test('is built from the opened text', () {
      final t = _build([
        _e2e(0, 'Shall we ship on Friday?'),
        _e2e(1, 'Yes, notes by Thursday.', isMine: true),
      ]);
      expect(t.count, 2);
      expect(t.text, contains('ana: Shall we ship on Friday?'));
      expect(t.text, contains('me (you): Yes, notes by Thursday.'));
      expect(t.text, isNot(contains('e2e1:')));
    });

    test('an unreadable message is one line with the chat\'s lock wording', () {
      final t = _build([
        _e2e(0, 'Hello'),
        _e2e(1, '', state: 'cant_decrypt', code: 'not_for_this_device'),
        _e2e(2, '', state: 'cant_decrypt', code: 'unknown_sender_device'),
        _e2e(3, '', state: 'cant_decrypt'),
      ]);
      expect(t.count, 4);
      expect(
        t.text,
        contains('ana: ${E2eTexts.unreadableFor('not_for_this_device')}'),
      );
      expect(
        t.text,
        contains('ana: ${E2eTexts.unreadableFor('unknown_sender_device')}'),
      );
      expect(t.text, contains('ana: ${E2eTexts.unreadable}'));
      expect(t.text, isNot(contains(_envelope)));
    });

    test('a message still being opened is left out', () {
      final t = _build([_e2e(0, 'Hello'), _e2e(1, '', state: 'pending')]);
      expect(t.count, 1);
      expect(t.text, isNot(contains(_envelope)));
      expect(t.text, contains('1 message, '));
    });

    test(
      'a reply to an unreadable message quotes the lock line, not the envelope',
      () {
        final t = _build([
          _e2e(0, '', state: 'cant_decrypt', code: 'decrypt_failed'),
          _e2e(1, 'What did you mean?', isMine: true, replyTo: 'm0'),
        ]);
        expect(t.text, contains('(reply to ana: "🔒 This message is damaged'));
        expect(t.text, isNot(contains(_envelope)));
      },
    );

    test('a chat of only unreadable messages is still not ciphertext', () {
      final t = _build([_e2e(0, '', state: 'cant_decrypt')]);
      expect(t.count, 1);
      expect(t.text, isNot(contains(_envelope)));
    });
  });

  group('the repository on an end-to-end chat', () {
    Future<(FakeSocket, _Rows, List<String>)> run() async {
      final socket = FakeSocket()..goOnline();
      final rows = _Rows([
        _e2e(0, 'Shall we ship on Friday?'),
        _e2e(1, '', state: 'cant_decrypt', code: 'not_for_this_device'),
        _e2e(2, 'Yes.', isMine: true),
        _e2e(3, '', state: 'pending'),
      ]);
      socket.answers['assistant.relay'] = {
        'status': 200,
        'body': {
          'content': [
            {'type': 'text', 'text': 'They agreed to ship on Friday.'},
          ],
        },
      };
      final repo = AiRepositoryImpl(
        socket,
        FakeStore(),
        rows,
        clock: () => DateTime(2026, 11, 11, 10),
      );
      final logged = <String>[];
      final old = debugPrint;
      debugPrint = (m, {wrapWidth}) => logged.add(m ?? '');
      try {
        await runZoned(
          () => repo
              .summarize(
                const AiSummaryRequest(
                  chatId: 'dm:ana',
                  title: 'Ana',
                  range: AiRange.everything,
                  agent: claude,
                ),
              )
              .single,
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => logged.add(line),
          ),
        );
      } finally {
        debugPrint = old;
      }
      await repo.dispose();
      return (socket, rows, logged);
    }

    test('the opened messages are awaited, then read', () async {
      final (_, rows, _) = await run();
      expect(rows.order, ['settle', 'read']);
    });

    test(
      'the prompt holds opened text and lock lines, never the envelope',
      () async {
        final (socket, _, _) = await run();
        final payload = socket.calls.single.args['payload'] as Map;
        final system = payload['system'] as String;
        final all = '$system ${payload['messages']}';
        expect(system, contains('ana: Shall we ship on Friday?'));
        expect(system, contains('me (you): Yes.'));
        expect(system, contains(E2eTexts.unreadableFor('not_for_this_device')));
        expect(system, contains('3 messages, '));
        expect(all, isNot(contains('e2e1:')));
        expect(all, isNot(contains('SECRETCIPHERTEXT')));
      },
    );

    test('nothing about the messages or the answer is logged', () async {
      final (_, _, logged) = await run();
      expect(logged, isEmpty);
    });
  });
}
