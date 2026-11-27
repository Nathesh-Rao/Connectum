import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/repositories/task_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Feed extends Fake implements FeedRepository {}

class _Tasks extends Fake implements TaskRepository {}

class _Tickets extends Fake implements TicketRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const approvals = Destination(DestinationKind.approvals);

  NotificationRouter make(FakeStore store) =>
      NotificationRouter(store, _Feed(), _Tasks(), _Tickets());

  test('a tap with the home up opens the Inbox with the approvals pane', () {
    final router = make(FakeStore(user: 'ana'));
    var opened = 0;
    router.openApprovals = () => opened++;
    router.markHomeReady();
    router.handle(approvals);
    expect(opened, 1);
    expect(router.pending, isNull);
  });

  test(
    'a cold start keeps the tap until the home is ready, then opens it',
    () async {
      final router = make(FakeStore(user: 'ana'));
      router.handle(approvals);
      expect(router.pending?.kind, DestinationKind.approvals);
      var opened = 0;
      router.openApprovals = () => opened++;
      router.markHomeReady();
      await Future<void>.delayed(Duration.zero);
      expect(opened, 1);
      expect(router.pending, isNull);
    },
  );

  test('signed out: kept, not opened', () async {
    final store = FakeStore(user: 'ana')..switchTo(null);
    final router = make(store);
    var opened = 0;
    router.openApprovals = () => opened++;
    router.markHomeReady();
    router.handle(approvals);
    await Future<void>.delayed(Duration.zero);
    expect(opened, 0);
    expect(router.pending?.kind, DestinationKind.approvals);
  });
}
