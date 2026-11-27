import 'package:connectum/data/repositories/feed_repository.dart';
import 'package:connectum/data/repositories/task_repository.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

class _Feed extends Fake implements FeedRepository {}

class _Tasks extends Fake implements TaskRepository {}

class _Tickets extends Fake implements TicketRepository {}

FeedItem newSubmission(Map<String, dynamic> ref) => FeedItem(
  id: 'sub:7',
  actionType: 'submissions',
  title: 'New submission: leave',
  ref: ref,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NotificationRouter make(FakeStore store) =>
      NotificationRouter(store, _Feed(), _Tasks(), _Tickets());

  group('"New submission" opens that record in the Inbox', () {
    test('the record number is the submission id', () {
      final d = NotificationRouter.resolve(
        newSubmission({'submissionId': 42, 'tstruct': 'leave'}),
      );
      expect(d.kind, DestinationKind.submission);
      expect(NotificationRouter.submissionIdOf(d), 42);
    });

    test('a bad or missing number has no record to open', () {
      for (final id in ['abc', '', '0', '-3', null]) {
        final d = Destination.submission(id ?? '', 'leave');
        expect(NotificationRouter.submissionIdOf(d), isNull, reason: '$id');
      }
      expect(
        NotificationRouter.submissionIdOf(
          const Destination(DestinationKind.submissions),
        ),
        isNull,
      );
    });

    test('a tap with the home up asks for the record, not the sheet', () {
      final router = make(FakeStore(user: 'ana'));
      final opened = <int>[];
      var list = 0;
      router.openRecord = opened.add;
      router.openInboxList = () => list++;
      router.markHomeReady();
      router.handleItem(newSubmission({'submissionId': '42'}));
      expect(opened, [42]);
      expect(list, 0);
      expect(router.pending, isNull);
    });

    test('a number that is not one opens the usual Inbox list', () {
      final router = make(FakeStore(user: 'ana'));
      final opened = <int>[];
      var list = 0;
      router.openRecord = opened.add;
      router.openInboxList = () => list++;
      router.markHomeReady();
      router.handleItem(newSubmission({'submissionId': 'abc'}));
      expect(opened, isEmpty);
      expect(list, 1);
    });

    test('a cold start keeps the tap until the home is ready', () async {
      final router = make(FakeStore(user: 'ana'));
      router.handleItem(newSubmission({'submissionId': 9}));
      expect(router.pending?.kind, DestinationKind.submission);
      final opened = <int>[];
      router.openRecord = opened.add;
      router.markHomeReady();
      await Future<void>.delayed(Duration.zero);
      expect(opened, [9]);
      expect(router.pending, isNull);
    });

    test('signed out: kept, not opened', () async {
      final store = FakeStore(user: 'ana')..switchTo(null);
      final router = make(store);
      final opened = <int>[];
      router.openRecord = opened.add;
      router.markHomeReady();
      router.handleItem(newSubmission({'submissionId': 9}));
      await Future<void>.delayed(Duration.zero);
      expect(opened, isEmpty);
      expect(router.pending?.kind, DestinationKind.submission);
    });

    test('with no record number the item opens the Inbox Records list', () async {
      final d = NotificationRouter.resolve(newSubmission({}));
      expect(d.kind, DestinationKind.submissions);
      final router = make(FakeStore(user: 'ana'));
      final opened = <int>[];
      var list = 0;
      router.openRecord = opened.add;
      router.openInboxList = () => list++;
      router.markHomeReady();
      router.handleItem(newSubmission({}));
      expect(opened, isEmpty);
      expect(list, 1);
    });

    test('with no record number a cold start keeps the tap', () async {
      final router = make(FakeStore(user: 'ana'));
      router.handleItem(newSubmission({}));
      expect(router.pending?.kind, DestinationKind.submissions);
      var list = 0;
      router.openInboxList = () => list++;
      router.markHomeReady();
      await Future<void>.delayed(Duration.zero);
      expect(list, 1);
    });
  });
}
