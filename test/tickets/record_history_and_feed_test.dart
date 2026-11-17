import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/form_entry.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:connectum/features/tickets/models/record_history_card.dart';
import 'package:flutter_test/flutter_test.dart';

FormCardData card({
  required String id,
  String structure = 'record_history',
  List<FormEntry> entries = const [],
}) => FormCardData(
  id: id,
  caption: 'Record history',
  structure: structure,
  scope: '',
  by: 'ben',
  ts: 1,
  entries: entries,
);

void main() {
  group('the history card of a record conversation', () {
    final entries = [
      const FormEntry(name: 'structure', caption: 'Structure', text: 'Ticket'),
      const FormEntry(name: 'record', caption: 'Record', text: '24'),
      const FormEntry(name: 'event', caption: 'Event', text: 'Status'),
      const FormEntry(name: 'by', caption: 'By', text: 'Ben Iyer'),
    ];

    test('it is recognised by its structure', () {
      expect(RecordHistoryCard.isCard(card(id: '9001')), isTrue);
      expect(
        RecordHistoryCard.isCard(card(id: '9001', structure: 'help_ticket')),
        isFalse,
      );
    });

    test("its submissionId (the history row) is never the record id", () {
      final c = card(id: '9001', entries: entries);
      expect(RecordHistoryCard.recordIdOf(c), 24);
      expect(RecordHistoryCard.recordIdOf(c), isNot(9001));
    });

    test('without a Record field there is nothing to open', () {
      expect(RecordHistoryCard.recordIdOf(card(id: '9001')), isNull);
      expect(
        RecordHistoryCard.recordIdOf(
          card(
            id: '9001',
            entries: const [
              FormEntry(name: 'record', caption: 'Record', text: 'n/a'),
            ],
          ),
        ),
        isNull,
      );
    });

    test('a "#24" style value still gives 24', () {
      expect(
        RecordHistoryCard.recordIdOf(
          card(
            id: '9001',
            entries: const [
              FormEntry(name: 'record', caption: 'Record', text: '#24'),
            ],
          ),
        ),
        24,
      );
    });
  });

  group('the "is with you" notification', () {
    final feed = FeedItem.tryParse({
      'id': 'sub-24',
      'ts': 1794393439190,
      'category': 'submissions',
      'title': 'Ticket #24 is with you',
      'message': 'Printer is jammed',
      'actionType': 'tickets',
      'actionLabel': 'Open ticket',
      'ref': {'submissionId': 24, 'tstruct': 'help_ticket'},
      'from': 'ana',
    })!;

    test('it opens the record by ref.submissionId', () {
      final d = NotificationRouter.resolve(feed);
      expect(d.kind, DestinationKind.ticket);
      expect(NotificationRouter.ticketIdOf(d), 24);
      expect(d.tstruct, 'help_ticket');
    });

    test('there is no chat or deep link to follow', () {
      expect(feed.chatId, isNull);
      expect(feed.actionLabel, 'Open ticket');
    });

    test('a number in text form still opens it', () {
      final d = NotificationRouter.resolve(
        FeedItem.tryParse({
          'id': 'sub-24',
          'actionType': 'tickets',
          'ref': {'submissionId': '24', 'tstruct': 'help_ticket'},
        })!,
      );
      expect(NotificationRouter.ticketIdOf(d), 24);
    });
  });
}
