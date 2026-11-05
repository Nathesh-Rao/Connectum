import 'package:connectum/data/models/approval.dart';
import 'package:connectum/data/models/ticket.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/models/feed_reducer.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/postman.dart';

/// The sample replies of the Postman collection (folders 5, 6 and 8), run
/// through the parsers and reducers the app uses.
void main() {
  final p = Postman.instance;

  group('feed', () {
    test('feed.list: the API message item, with its counts', () {
      final data = p.data('feed.list filtered');
      final item = FeedItem.tryParse((data['notifications'] as List).first)!;
      expect(item.category, 'api');
      expect(item.priority, 'high');
      expect(item.outcome, 'error');
      expect(item.httpStatus, 500);
      expect(item.source, 'Leave API');
      expect(item.via, 'api:Leave API');
      expect(item.isRead, isFalse);
      expect(item.actionType, isNull);
      expect(NotificationRouter.resolve(item).kind, DestinationKind.none);
      final counts = FeedCounts.tryParse(data['counts'])!;
      expect(
        (counts.high, counts.medium, counts.unread, counts.total),
        (1, 2, 3, 3),
      );
    });

    test(
      'feed.list: every item of the full list parses and keeps the order the reducer gives',
      () {
        final data = p.data(
          '8. My Workspace feed, real replies (3 November 2026)/feed.list',
        );
        final items = [
          for (final j in data['notifications'] as List) ?FeedItem.tryParse(j),
        ];
        expect(items.length, (data['notifications'] as List).length);
        final replaced = FeedReducer.replace(items);
        for (var i = 1; i < replaced.length; i++) {
          expect(replaced[i - 1].ts, greaterThanOrEqualTo(replaced[i].ts));
        }
      },
    );

    test('feed.summary has no counts wrapper', () {
      final c = FeedCounts.tryParse(p.data('feed.summary'))!;
      expect(c.total, 3);
      expect(c.forPriority('high'), 1);
      expect(c.forPriority('all'), 3);
    });

    test('feed.read, read false and read all: counts', () {
      expect(FeedCounts.tryParse(p.data('feed.read')['counts'])!.unread, 2);
      expect(
        FeedCounts.tryParse(p.data('feed.read false')['counts'])!.unread,
        3,
      );
      expect(FeedCounts.tryParse(p.data('feed.read all')['counts'])!.unread, 0);
    });

    test('feed.resolve: the resolved item replaces the open one', () {
      final data = p.data(
        '8. My Workspace feed, real replies (3 November 2026)/feed.resolve',
      );
      final item = FeedItem.tryParse(data['notification'])!;
      expect(item.isResolved, isTrue);
      expect(item.priority, 'resolved');
      expect(item.resolvedTs, isNotNull);
      final open = item.copyWith(priority: 'high', isResolved: false);
      final list = FeedReducer.applyItem([open], item);
      expect(list.single.isResolved, isTrue);
      expect(
        FeedReducer.filter(list, priority: 'all', isUnreadOnly: false),
        isEmpty,
      );
      expect(
        FeedReducer.filter(list, priority: 'resolved', isUnreadOnly: false),
        hasLength(1),
      );
    });

    test('feed.dismiss and feed.clear counts', () {
      expect(FeedCounts.tryParse(p.data('feed.dismiss')['counts'])!.total, 2);
      expect(FeedCounts.tryParse(p.data('feed.clear')['counts'])!.total, 0);
    });

    test(
      'the four real feed refusals have the code and text the app shows',
      () {
        expect(p.error('feed.list bad priority')['code'], 'invalid');
        expect(p.error('feed.read nothing')['code'], 'invalid');
        expect(p.error('feed.resolve unknown')['code'], 'not_found');
        expect(
          p.error('feed.dismiss again')['message'],
          'No such notification.',
        );
      },
    );
  });

  group('approvals', () {
    test('req.list: waiting for me is answerable, the sender view is not', () {
      final waiting = ApprovalPage.parse(
        p.data('req.list: an approval waiting for me'),
      );
      expect(waiting.requests.single.canRespond, isTrue);
      expect(waiting.requests.single.isIncoming, isTrue);
      expect(waiting.requests.single.isSubmission, isTrue);
      final sent = ApprovalPage.parse(p.data('req.list: what the sender sees'));
      expect(sent.requests.single.isOutgoing, isTrue);
      expect(sent.requests.single.canRespond, isFalse);
      expect(sent.requests.single.status, 'accepted');
    });

    test('the sign-up the administrator answers, and the declined one', () {
      final page = ApprovalPage.parse(
        p.data('req.list: a sign-up waiting (administrator)'),
      );
      expect(page.requests.single.canRespond, isTrue);
      expect(page.requests.single.isSubmission, isFalse);
    });

    test('req.respond refusal: already_resolved', () {
      expect(
        p.error('req.respond: answering again is refused')['code'],
        'already_resolved',
      );
    });
  });

  group('tickets', () {
    test('status.update answers: ok, a repeat, stale, forbidden', () {
      final ok = TicketUpdateResult.parse(
        p.data('status.update: a status update'),
      );
      expect(ok.status, 'In progress');
      expect(ok.isRepeated, isFalse);
      final again = TicketUpdateResult.parse(
        p.data('status.update: the same request again'),
      );
      expect(again.isRepeated, isTrue);
      expect(again.completion, ok.completion);
      expect(
        p.error('status.update: someone else got there first')['code'],
        'stale',
      );
      expect(
        p.error('status.update: not for this person')['code'],
        'forbidden',
      );
    });

    test('ticket_assigned event', () {
      final event = p.reply('event: ticket_assigned');
      final data = (event['data'] as Map).cast<String, dynamic>();
      final a = TicketAssigned.tryParse(data)!;
      expect(
        (a.id, a.tstruct, a.action, a.by),
        (38, 'help_ticket', 'Raised', 'rhea'),
      );
    });
  });
}
