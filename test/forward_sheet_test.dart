import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/features/conversation/models/forward.dart';
import 'package:connectum/features/conversation/widgets/forward_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation conv(String id) =>
    Conversation(convId: id, kind: 'dm', title: id.split(':').last);

void main() {
  testWidgets('tapping a row selects it, again clears it, button follows', (
    tester,
  ) async {
    final picker = ForwardPicker(targets: [conv('dm:ann'), conv('dm:bob')]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ForwardSheet(
              onSend: (_) {},
              message: Message(
                msgId: '1',
                convId: 'dm:ann',
                sender: 'ann',
                isMine: false,
                text: 'hi',
                ts: 1,
                status: MessageStatus.sent,
              ),
              picker: picker,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Send'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    double scaleOf(int i) =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale).at(i)).scale;
    expect(scaleOf(0), 0);

    await tester.tap(find.text('ann'));
    await tester.pumpAndSettle();
    expect(scaleOf(0), 1);
    expect(scaleOf(1), 0);
    expect(find.text('Send to 1'), findsOneWidget);

    await tester.tap(find.text('ann'));
    await tester.pumpAndSettle();
    expect(scaleOf(0), 0);
    expect(find.text('Send'), findsOneWidget);
  });
}
