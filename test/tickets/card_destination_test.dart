import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/record_live.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:connectum/features/tickets/models/card_destination.dart';
import 'package:flutter_test/flutter_test.dart';

FormCardData _card(
  String id, {
  RecordSummary? record,
  bool isReadOnly = false,
  bool hasResult = false,
  String structure = 'help_ticket',
}) => FormCardData(
  id: id,
  caption: 'Help ticket',
  structure: structure,
  scope: 'user',
  by: 'rhea',
  ts: 1,
  entries: const [],
  record: record,
  isReadOnly: isReadOnly,
  hasResult: hasResult,
);

void main() {
  final ticket = AppRoutes.ticketOf(42);

  test('v0.2.19: a record with a summary opens the ticket', () {
    final card = _card(
      '42',
      record: const RecordSummary(status: 'Open', holder: 'ana'),
    );
    expect(CardDestination.of(card), ticket);
  });

  test('no summary (unknown) still opens the ticket', () {
    expect(CardDestination.of(_card('42')), ticket);
  });

  test('an older record without a summary opens the ticket', () {
    expect(CardDestination.of(_card('42', record: null)), ticket);
  });

  test('a received record opens the ticket', () {
    expect(CardDestination.of(_card('42')), ticket);
  });

  test('plain submissions open the submission detail', () {
    expect(
      CardDestination.of(_card('c-9')),
      AppRoutes.submissionDetailOf('c-9'),
    );
    expect(
      CardDestination.of(_card('42', isReadOnly: true)),
      AppRoutes.submissionDetailOf('42'),
    );
    expect(
      CardDestination.of(_card('42', hasResult: true)),
      AppRoutes.submissionDetailOf('42'),
    );
  });

  test('the same item by chat card and by notification: same screen', () {
    final fromChat = CardDestination.of(
      _card('42'),
      convId: 'dm:ana',
      msgId: '7',
    );
    final id = NotificationRouter.ticketIdOf(
      const Destination.ticket('42', 'help_ticket'),
    );
    expect(fromChat, ticket);
    expect(AppRoutes.ticketOf(id!), fromChat);
  });
}
