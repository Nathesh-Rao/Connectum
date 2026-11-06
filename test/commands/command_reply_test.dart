import 'package:connectum/data/commands/command_reply.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

CommandSuggestions _answer(String input, int reqId) =>
    CommandSuggestions(input: input, reqId: reqId, kind: 'arg');

void main() {
  group('suggester', () {
    test('waits 150 ms after the last change and asks once', () {
      fakeAsync((async) {
        final asked = <String>[];
        final s = CommandSuggester((input, page, reqId) async {
          asked.add(input);
          return _answer(input, reqId);
        });
        final got = <String>[];
        s.onResult = (r, {required isMore}) => got.add(r.input);
        s.request('#dm a');
        async.elapse(const Duration(milliseconds: 100));
        s.request('#dm an');
        async.elapse(const Duration(milliseconds: 100));
        expect(asked, isEmpty);
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();
        expect(asked, ['#dm an']);
        expect(got, ['#dm an']);
      });
    });

    test('a slow older reply is ignored', () {
      fakeAsync((async) {
        final s = CommandSuggester((input, page, reqId) async {
          await Future<void>.delayed(
            input.endsWith('a') ? const Duration(seconds: 1) : Duration.zero,
          );
          return _answer(input, reqId);
        });
        final got = <int>[];
        s.onResult = (r, {required isMore}) => got.add(r.reqId);
        s.request('#dm a');
        async.elapse(const Duration(milliseconds: 160));
        s.request('#dm r');
        async.elapse(const Duration(milliseconds: 160));
        async.elapse(const Duration(seconds: 2));
        expect(got, [2]);
      });
    });

    test('over 512 bytes is not sent', () {
      fakeAsync((async) {
        var asked = 0;
        final s = CommandSuggester((i, p, r) async {
          asked++;
          return null;
        });
        s.request('#dm ${'é' * 300}');
        async.elapse(const Duration(seconds: 1));
        expect(asked, 0);
        expect(CommandSuggester.fits('é' * 256), isTrue);
        expect(CommandSuggester.fits('é' * 257), isFalse);
      });
    });

    test('nothing arrives after dispose', () {
      fakeAsync((async) {
        final s = CommandSuggester((i, p, r) async => _answer(i, r));
        var got = 0;
        s.onResult = (r, {required isMore}) => got++;
        s.request('#dm a');
        s.dispose();
        async.elapse(const Duration(seconds: 1));
        expect(got, 0);
      });
    });
  });

  group('frames to results', () {
    test('error frames', () {
      final r = CommandReply.fromFrame({
        'type': 'error',
        'code': 'unknown_command',
        'text': '#xyz is not a command.',
        'suggestions': ['dm', 'users'],
      }, name: 'xyz')!;
      expect(r.isOk, isFalse);
      expect(r.code, 'unknown_command');
      expect(r.suggestions, ['dm', 'users']);
      final usage = CommandReply.fromFrame({
        'type': 'error',
        'code': 'usage',
        'text': 'Missing text. Usage: #dm <user> <text...>',
      }, name: 'dm')!;
      expect(usage.message, 'Missing text. Usage: #dm <user> <text...>');
    });

    test('a chat error of a conversation is not an answer', () {
      expect(
        CommandReply.fromFrame({
          'type': 'error',
          'conv': 'dm:ana',
          'text': 'x',
        }, name: 'dm'),
        isNull,
      );
    });

    test('rate limit and internal', () {
      expect(
        CommandReply.fromFrame({
          'type': 'error',
          'text': 'Too many commands -- slow down',
        }, name: 'x')!.message,
        'Too many commands. Wait a moment and try again.',
      );
      expect(
        CommandReply.fromFrame({
          'type': 'error',
          'code': 'internal',
        }, name: 'x')!.message,
        'Something went wrong running that command.',
      );
    });

    test('dm_ack, group_created, left_group', () {
      expect(
        CommandReply.fromFrame(
          {'type': 'dm_ack'},
          name: 'dm',
          replies: ['dm_ack'],
        )!.isOk,
        isTrue,
      );
      expect(
        CommandReply.fromFrame(
          {'type': 'group_created', 'name': 'g'},
          name: 'creategroup',
          replies: ['group_created'],
        )!.frame['name'],
        'g',
      );
      expect(
        CommandReply.fromFrame(
          {'type': 'left_group', 'text': 'g'},
          name: 'leavegroup',
          replies: ['left_group'],
        ),
        isNotNull,
      );
      expect(
        CommandReply.fromFrame(
          {'type': 'group_invite_pending'},
          name: 'addmember',
          replies: ['group_created'],
        ),
        isNotNull,
      );
      expect(
        CommandReply.fromFrame(
          {'type': 'users'},
          name: 'groups',
          replies: ['groups'],
        ),
        isNull,
      );
    });

    test('duplicate:true is a normal ack', () {
      final r = CommandReply.fromFrame(
        {'type': 'group_created', 'duplicate': true},
        name: 'creategroup',
        replies: ['group_created'],
      )!;
      expect(r.isOk, isTrue);
      expect(r.isDuplicate, isTrue);
    });

    test('sd with reqId "#name"', () {
      final ok = CommandReply.fromFrame({
        'type': 'sd',
        'reqId': '#associates',
        'ok': true,
        'data': {'associates': []},
      }, name: 'associates')!;
      expect(ok.isOk, isTrue);
      expect(ok.frame['associates'], isEmpty);
      final bad = CommandReply.fromFrame({
        'type': 'sd',
        'reqId': '#associates',
        'ok': false,
        'error': {'code': 'forbidden', 'message': 'No.'},
      }, name: 'associates')!;
      expect(bad.isOk, isFalse);
      expect(bad.message, 'No.');
      expect(
        CommandReply.fromFrame({
          'type': 'sd',
          'reqId': 'm-1',
          'ok': true,
        }, name: 'associates'),
        isNull,
      );
    });
  });
}
