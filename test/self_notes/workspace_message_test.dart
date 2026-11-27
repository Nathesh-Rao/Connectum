import 'dart:io';

import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/models/self_conversation.dart';
import 'package:connectum/features/workspace/widgets/workspace_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Message _note(
  String id, {
  String text = 'a note',
  int ts = 1700000000000,
  bool isEncrypted = false,
  String? decryptState,
  String? plaintext,
  int? editedTs,
  String? replyTo,
  MessageStatus status = MessageStatus.sent,
  String? failReason,
}) => Message(
  msgId: id,
  convId: 'self',
  sender: 'ana',
  isMine: true,
  text: text,
  ts: ts,
  status: status,
  failReason: failReason,
  isEncrypted: isEncrypted,
  decryptState: decryptState,
  unreadableCode: decryptState == 'cant_decrypt' ? plaintext : null,
  editedTs: editedTs,
  replyTo: replyTo,
);

Future<void> _show(WidgetTester tester, List<Widget> children) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.5),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ),
      ),
    ),
  );
}

Future<void> _loadFont() async {
  final loader = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadFont);
  final quoted = _note('1', text: 'the first note of the day');
  final cases = <String, Widget>{
    'plain': WorkspaceMessage(message: quoted, original: null, me: 'ana'),
    'long, edited, quoting a loaded note': WorkspaceMessage(
      message: _note(
        '2',
        text: 'a long note ' * 20,
        editedTs: 1700000100000,
        replyTo: '1',
      ),
      original: quoted,
      me: 'ana',
    ),
    'quote not loaded': WorkspaceMessage(
      message: _note('3', replyTo: '99'),
      original: null,
      me: 'ana',
    ),
    'locked': WorkspaceMessage(
      message: _note(
        '4',
        text: 'e2e1:{}',
        isEncrypted: true,
        decryptState: 'cant_decrypt',
        plaintext: 'not_for_this_device',
      ),
      original: null,
      me: 'ana',
    ),
    'pending': WorkspaceMessage(
      message: _note('temp-1', status: MessageStatus.pending),
      original: null,
      me: 'ana',
    ),
    'sending': WorkspaceMessage(
      message: _note('temp-2', status: MessageStatus.sending),
      original: null,
      me: 'ana',
    ),
    'failed': WorkspaceMessage(
      message: _note(
        'temp-3',
        text: 'a long failed note ' * 10,
        status: MessageStatus.failed,
        failReason:
            'e2e:Can\'t send securely right now: this phone isn\'t registered',
      ),
      original: null,
      me: 'ana',
    ),
    'too old': WorkspaceMessage(
      message: _note(
        'temp-4',
        status: MessageStatus.failed,
        failReason: SelfConversation.tooOld,
      ),
      original: null,
      me: 'ana',
    ),
    'waiting for encryption': WorkspaceMessage(
      message: _note(
        'temp-5',
        status: MessageStatus.pending,
        failReason: SelfConversation.waitingForEncryption,
      ),
      original: null,
      me: 'ana',
    ),
    'opened': WorkspaceMessage(
      message: _note(
        '5',
        text: 'e2e1:{}',
        isEncrypted: true,
        decryptState: 'ok',
        plaintext: 'opened text',
        editedTs: 1,
      ),
      original: null,
      me: 'ana',
    ),
  };
  for (final entry in cases.entries) {
    testWidgets('${entry.key}: 320 px, text scale 1.5, no overflow', (
      tester,
    ) async {
      await _show(tester, [entry.value]);
      expect(tester.takeException(), isNull);
      expect(tester.getTopRight(find.byType(WorkspaceMessage)).dx, 304);
    });
  }

  testWidgets('a locked note says why, an edited one says edited', (
    tester,
  ) async {
    await _show(tester, [cases['locked']!, cases['opened']!]);
    expect(tester.takeException(), isNull);
    expect(find.textContaining("can't be opened here"), findsOneWidget);
    expect(find.textContaining('edited'), findsOneWidget);
  });

  testWidgets('pending, failed and waiting rows say so; a failed one retries', (
    tester,
  ) async {
    var retries = 0;
    await _show(tester, [
      cases['pending']!,
      cases['waiting for encryption']!,
      cases['too old']!,
      WorkspaceMessage(
        message: _note('temp-6', status: MessageStatus.failed),
        original: null,
        me: 'ana',
        onRetry: () => retries++,
      ),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Waiting for encryption'), findsOneWidget);
    expect(find.textContaining('Too old to confirm'), findsOneWidget);
    await tester.tap(find.text('Not sent. Tap to retry'));
    expect(retries, 1);
  });
}
