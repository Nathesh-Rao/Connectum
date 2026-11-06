import 'package:connectum/features/chats/models/chat_filter.dart';
import 'package:connectum/features/chats/widgets/chat_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  late Rx<ChatFilterKind> filter;
  late RxBool hasThreads;
  late RxInt unread;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatFilterBar(
          filter: filter,
          hasThreads: hasThreads,
          threadUnread: unread,
          onSelected: (k) => filter.value = k,
        ),
      ),
    ),
  );

  setUp(() {
    filter = ChatFilterKind.all.obs;
    hasThreads = false.obs;
    unread = 0.obs;
  });

  testWidgets('shows All and Direct & Teams, no Threads without threads', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Direct & Teams'), findsOneWidget);
    expect(find.text('Threads'), findsNothing);
  });

  testWidgets('Threads appears with its unread count and can be chosen', (
    tester,
  ) async {
    hasThreads.value = true;
    unread.value = 4;
    await pump(tester);
    expect(find.text('Threads'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.text('Threads'));
    await tester.pumpAndSettle();
    expect(filter.value, ChatFilterKind.threads);
    await tester.tap(find.text('Direct & Teams'));
    await tester.pumpAndSettle();
    expect(filter.value, ChatFilterKind.direct);
  });

  testWidgets('All and Direct & Teams carry no count', (tester) async {
    hasThreads.value = true;
    await pump(tester);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the Threads pill goes away when the last thread does', (
    tester,
  ) async {
    hasThreads.value = true;
    await pump(tester);
    hasThreads.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Threads'), findsNothing);
  });

  testWidgets('the compact pills start at the left edge and stay 28 high', (
    tester,
  ) async {
    await pump(tester);
    final first = tester.getTopLeft(find.text('All'));
    expect(first.dx, 10);
    final pill = find.ancestor(
      of: find.text('All'),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(pill).height, 28);
    expect(tester.getTopLeft(pill).dx, 0);
  });

  testWidgets('at text scale 1.3 the pills stay on one line', (tester) async {
    hasThreads.value = true;
    unread.value = 12;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SizedBox(
              width: 260,
              child: ChatFilterBar(
                filter: filter,
                hasThreads: hasThreads,
                threadUnread: unread,
                onSelected: (k) => filter.value = k,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final h = tester.getSize(find.text('Direct & Teams')).height;
    expect(h, lessThan(30));
  });
}
