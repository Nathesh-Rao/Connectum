import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/repositories/message_repository.dart';
import 'package:connectum/features/conversation/models/forward.dart';
import 'package:flutter_test/flutter_test.dart';

Message msg(
  String text, {
  bool isMine = false,
  String sender = 'ann',
  String kind = 'chat',
  bool isDeleted = false,
  bool isEncrypted = false,
  String? decryptState,
  MessageStatus status = MessageStatus.sent,
}) => Message(
  msgId: '1',
  convId: 'dm:ann',
  sender: sender,
  isMine: isMine,
  text: text,
  ts: 1,
  status: status,
  kind: kind,
  isDeleted: isDeleted,
  isEncrypted: isEncrypted,
  decryptState: decryptState,
);

const plainTag =
    '[ATTACHMENT:{"kind":"file","name":"a.pdf","size":"1 KB","url":"/uploads/a.pdf","type":"application/pdf"}]';
const sealedTag =
    '[ATTACHMENT:{"kind":"file","name":"a.pdf","size":"1 KB","url":"/uploads/a.e2e","type":"x","e2e":{"key":"k","iv":"i"}}]';

Conversation conv(String id, {bool isEncrypted = false}) => Conversation(
  convId: id,
  kind: id.split(':').first,
  title: id,
  isEncrypted: isEncrypted,
);

const blobNoKey =
    '[ATTACHMENT:{"kind":"file","name":"a.pdf","size":"1 KB","url":"/uploads/a.e2e","type":"x"}]';

void main() {
  group('forward text', () {
    test('my own message has no author', () {
      expect(
        Forward.text(msg('hi', isMine: true), forwarder: 'Me', author: 'Me'),
        '↪ [Forwarded by Me]: hi',
      );
    });

    test("someone else's message names the author", () {
      expect(
        Forward.text(msg('hi'), forwarder: 'Me', author: 'Ann Lee'),
        '↪ [Forwarded by Me • from Ann Lee]: hi',
      );
    });

    test('a forward of a forward shows one banner and keeps the author', () {
      expect(
        Forward.text(
          msg('↪ [Forwarded by Bob • from Cy]: hi'),
          forwarder: 'Me',
          author: 'Bob',
        ),
        '↪ [Forwarded by Me • from Cy]: hi',
      );
      expect(
        Forward.text(
          msg('↪ [Forwarded by Bob]: hi', sender: 'bob'),
          forwarder: 'Me',
          author: 'bob',
        ),
        '↪ [Forwarded by Me • from bob]: hi',
      );
    });

    test('a file without text uses its name', () {
      expect(
        Forward.text(msg(plainTag), forwarder: 'Me', author: 'Ann'),
        '↪ [Forwarded by Me • from Ann]: a.pdf $plainTag',
      );
    });
  });

  group('who sees Forward', () {
    test('text, plain file', () {
      expect(Forward.canForward(msg('hi')), isTrue);
      expect(Forward.canForward(msg(plainTag)), isTrue);
    });
    test('not deleted, form, failed or unreadable', () {
      expect(Forward.canForward(msg('hi', isDeleted: true)), isFalse);
      expect(Forward.canForward(msg('hi', kind: 'form')), isFalse);
      expect(
        Forward.canForward(msg('hi', status: MessageStatus.failed)),
        isFalse,
      );
      expect(
        Forward.canForward(
          msg('hi', isEncrypted: true, decryptState: 'failed'),
        ),
        isFalse,
      );
      expect(Forward.canForward(msg(blobNoKey)), isFalse);
      expect(
        Forward.canForward(msg('hi', isEncrypted: true, decryptState: 'ok')),
        isTrue,
      );
    });
  });

  group('attachments', () {
    test(
      'a sealed file can be forwarded and its tag is kept byte for byte',
      () {
        final m = msg(sealedTag, isEncrypted: true, decryptState: 'ok');
        expect(Forward.canForward(m), isTrue);
        final out = Forward.text(m, forwarder: 'Me', author: 'Ann');
        expect(out, '↪ [Forwarded by Me • from Ann]: a.pdf $sealedTag');
        expect(out.endsWith(sealedTag), isTrue);
      },
    );
    test('a caption is kept and the name is not added', () {
      final out = Forward.text(
        msg('see $plainTag'),
        forwarder: 'Me',
        author: 'Ann',
      );
      expect(out, '↪ [Forwarded by Me • from Ann]: see $plainTag');
    });
    test(
      'a sealed file goes only to encrypted chats, a plain one to plain',
      () {
        final plainChat = conv('dm:bob', isEncrypted: false);
        final sealedChat = conv('dm:cy', isEncrypted: true);
        final sealed = msg(sealedTag, isEncrypted: true, decryptState: 'ok');
        expect(Forward.canGoTo(sealed, sealedChat), isTrue);
        expect(Forward.canGoTo(sealed, plainChat), isFalse);
        expect(Forward.canGoTo(msg(plainTag), plainChat), isTrue);
        expect(Forward.canGoTo(msg(plainTag), sealedChat), isFalse);
        expect(Forward.canGoTo(msg('hi'), sealedChat), isTrue);
        expect(Forward.canGoTo(msg('hi'), conv('host:x')), isFalse);
      },
    );
    test('the sheet preview names the kind and the file', () {
      expect(Forward.previewOf(msg(plainTag)), 'File · a.pdf');
      expect(Forward.previewOf(msg('hello')), 'hello');
    });
  });

  group('the # guard', () {
    test('@ is allowed at the start and in the middle', () {
      expect(MessageRepository.isCommandLike('@ann hello'), isFalse);
      expect(MessageRepository.isCommandLike('hello @ann'), isFalse);
    });
    test('#command is blocked', () {
      expect(MessageRepository.isCommandLike('#help'), isTrue);
      expect(MessageRepository.isCommandLike('# not a command'), isFalse);
    });
  });
}
