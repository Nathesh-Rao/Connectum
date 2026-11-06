import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/notifications/feed_actions.dart';
import 'package:connectum/core/theme/app_spacing.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/widgets/feed_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSocket socket;
  late FeedRepository feed;
  var opened = 0;

  const item = FeedItem(
    id: 'a',
    priority: 'high',
    category: 'messages',
    title: 'Ana',
    message: 'Ana: lunch at one?',
    ts: 100,
    actionType: 'open_chat',
    actionLabel: 'Open chat',
    chatId: 'user-ana',
    from: 'ana',
  );

  setUp(() {
    opened = 0;
    socket = FakeSocket()..goOnline();
    feed = FeedRepository(socket, FakeStore(), FakeE2e())..onInit();
    feed.items.add(item);
  });

  tearDown(() => feed.onClose());

  Future<void> openSheet(WidgetTester tester, {bool isRoutable = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => FeedDetailSheet.show(
                context,
                item,
                text: Future.value(item.message),
                feed: feed,
                actions: FeedActions(feed),
                onOpen: isRoutable ? () => opened++ : null,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('title, priority, the three actions and the primary button', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('Ana'), findsWidgets);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Open chat'), findsOneWidget);
    expect(find.text('Mark read'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('the header has a category pill and no Category row', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Category'), findsNothing);
    final pill = find.ancestor(
      of: find.text('High'),
      matching: find.byType(Container),
    );
    expect(tester.getSize(pill.first).height, AppSpacing.priorityPillHeight);
    expect(tester.getSize(pill.first).width, lessThan(80));
  });

  testWidgets('the category pill is the label only, 28 dp, 12 dp padding', (
    tester,
  ) async {
    await openSheet(tester);
    final pill = find.ancestor(
      of: find.text('Messages'),
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: pill.first, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(tester.getSize(pill.first).height, AppSpacing.categoryPillHeight);
    final text = tester.getSize(find.text('Messages')).width;
    expect(tester.getSize(pill.first).width, text + 2 * AppSpacing.sm);
  });

  testWidgets('no primary button when the item leads nowhere', (tester) async {
    await openSheet(tester, isRoutable: false);
    expect(find.text('Open chat'), findsNothing);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('the primary button closes the sheet and opens the target', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Dismiss'), findsNothing);
  });

  testWidgets('mark read: optimistic, the label flips, the sheet stays', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.text('Mark read'));
    await tester.pumpAndSettle();
    expect(socket.count('feed.read'), 1);
    expect(find.text('Mark unread'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    await tester.pump(FeedRepository.burst);
  });

  testWidgets('resolve closes the sheet; a failure keeps it open', (
    tester,
  ) async {
    socket.answers['feed.resolve'] = const SocketCallError('forbidden', 'No.');
    await openSheet(tester);
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(find.text('Dismiss'), findsOneWidget);
    expect(feed.items.single.isResolved, isFalse);

    socket.answers.remove('feed.resolve');
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();
    expect(find.text('Dismiss'), findsNothing);
  });

  testWidgets('dismiss removes the item and closes the sheet', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(socket.count('feed.dismiss'), 1);
    expect(feed.items, isEmpty);
    expect(find.text('Dismiss'), findsNothing);
  });
}
