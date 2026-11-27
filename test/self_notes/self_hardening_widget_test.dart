import 'dart:io';

import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/models/self_conversation.dart';
import 'package:connectum/features/workspace/widgets/workspace_locked_hint.dart';
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

  testWidgets(
    'a note waiting long for encryption shows the setup line and opens it on tap',
    (tester) async {
      var taps = 0;
      await _show(tester, [
        WorkspaceMessage(
          message: _note(
            'temp-1',
            status: MessageStatus.pending,
            failReason: SelfConversation.waitingForSetup,
          ),
          original: null,
          me: 'ana',
          onSetUpEncryption: () => taps++,
        ),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text(SelfConversation.setupNeededLine), findsOneWidget);
      expect(find.text('Waiting for encryption'), findsNothing);
      await tester.tap(find.text(SelfConversation.setupNeededLine));
      expect(taps, 1);
    },
  );

  testWidgets(
    'a note that has waited less shows the quiet line, not the action',
    (tester) async {
      await _show(tester, [
        WorkspaceMessage(
          message: _note(
            'temp-2',
            status: MessageStatus.pending,
            failReason: SelfConversation.waitingForEncryption,
          ),
          original: null,
          me: 'ana',
          onSetUpEncryption: () {},
        ),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('Waiting for encryption'), findsOneWidget);
      expect(find.text(SelfConversation.setupNeededLine), findsNothing);
    },
  );

  testWidgets(
    'a locked note and the locked hint fit 320 px at text scale 1.5',
    (tester) async {
      var taps = 0;
      await _show(tester, [
        WorkspaceMessage(
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
        WorkspaceLockedHint(onTap: () => taps++),
      ]);
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Sent before this phone was set up'),
        findsOneWidget,
      );
      expect(find.text(SelfConversation.lockedNotesLine), findsOneWidget);
      await tester.ensureVisible(find.text(SelfConversation.lockedNotesLine));
      await tester.pump();
      await tester.tap(find.text(SelfConversation.lockedNotesLine));
      expect(taps, 1);
    },
  );

  testWidgets('a plain note is never drawn as locked', (tester) async {
    await _show(tester, [
      WorkspaceMessage(
        message: _note('5', text: 'just text'),
        original: null,
        me: 'ana',
      ),
    ]);
    expect(find.text('just text'), findsOneWidget);
    expect(find.textContaining('🔒'), findsNothing);
  });
}
