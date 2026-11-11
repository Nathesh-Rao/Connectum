import 'package:connectum/features/chats/models/chat_filter.dart';
import 'package:connectum/features/chats/widgets/chat_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  late Rx<ChatFilterKind> filter;
  late RxBool hasThreads;

  Widget host() => MaterialApp(
    home: Scaffold(
      body: ChatFilterBar(
        filter: filter,
        hasThreads: hasThreads,
        threadUnread: 0.obs,
        onSelected: (k) => filter.value = k,
      ),
    ),
  );

  setUp(() {
    filter = ChatFilterKind.threads.obs;
    hasThreads = true.obs;
  });

  testWidgets(
    'Threads stays selected and shown when the list empties and refills',
    (tester) async {
      await tester.pumpWidget(host());
      expect(find.text('Threads'), findsOneWidget);

      // A reload empties the list: hasThreads goes false.
      hasThreads.value = false;
      await tester.pump();
      expect(filter.value, ChatFilterKind.threads);
      expect(find.text('Threads'), findsOneWidget);

      hasThreads.value = true;
      await tester.pump();
      expect(filter.value, ChatFilterKind.threads);
    },
  );

  testWidgets('a rebuilt bar keeps the selection held in the controller', (
    tester,
  ) async {
    hasThreads.value = false;
    await tester.pumpWidget(host());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host());
    expect(filter.value, ChatFilterKind.threads);
    expect(find.text('Threads'), findsOneWidget);
  });

  testWidgets('only a tap leaves Threads', (tester) async {
    hasThreads.value = false;
    await tester.pumpWidget(host());
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(filter.value, ChatFilterKind.all);
    expect(find.text('Threads'), findsNothing);
  });
}
