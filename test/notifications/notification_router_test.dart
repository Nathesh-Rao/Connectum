import 'package:connectum/data/notifications/push/push_payload.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/notification_router.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem item({
  String? actionType,
  String? chatId,
  Map<String, dynamic> ref = const {},
}) => FeedItem(id: 'x', actionType: actionType, chatId: chatId, ref: ref);

void main() {
  DestinationKind kind(FeedItem i) => NotificationRouter.resolve(i).kind;

  test('open_chat: a direct chat and a group', () {
    final dm = NotificationRouter.resolve(
      item(actionType: 'open_chat', chatId: 'user-sam1'),
    );
    expect(dm.kind, DestinationKind.chat);
    expect(dm.conversationId, 'dm:sam1');
    final group = NotificationRouter.resolve(
      item(actionType: 'open_chat', chatId: 'room-sales team'),
    );
    expect(group.conversationId, 'group:sales team');
  });

  test('open_chat without a usable chat shows the detail', () {
    expect(kind(item(actionType: 'open_chat')), DestinationKind.detail);
    expect(
      kind(item(actionType: 'open_chat', chatId: 'weird')),
      DestinationKind.detail,
    );
  });

  test('open_message carries the message id', () {
    final d = NotificationRouter.resolve(
      item(
        actionType: 'open_message',
        chatId: 'room-g',
        ref: {'messageId': 77},
      ),
    );
    expect(d.kind, DestinationKind.message);
    expect(d.conversationId, 'group:g');
    expect(d.messageId, '77');
  });

  test('open_message without a message id opens the chat', () {
    final d = NotificationRouter.resolve(
      item(actionType: 'open_message', chatId: 'user-a'),
    );
    expect(d.kind, DestinationKind.chat);
    expect(d.conversationId, 'dm:a');
  });

  test('open_message without a chat shows the detail', () {
    expect(
      kind(item(actionType: 'open_message', ref: {'messageId': 1})),
      DestinationKind.detail,
    );
  });

  test('screens', () {
    expect(kind(item(actionType: 'approvals')), DestinationKind.approvals);
    expect(kind(item(actionType: 'tickets')), DestinationKind.tickets);
    expect(kind(item(actionType: 'submissions')), DestinationKind.submissions);
    expect(kind(item(actionType: 'tasks')), DestinationKind.tasks);
  });

  test('a ticket item with a submission opens that ticket', () {
    final d = NotificationRouter.resolve(
      item(
        actionType: 'tickets',
        ref: {'submissionId': 42, 'tstruct': 'leave'},
      ),
    );
    expect(d.kind, DestinationKind.ticket);
    expect(d.submissionId, '42');
    expect(d.tstruct, 'leave');
    expect(d, const Destination.ticket('42', 'leave'));
  });

  test('a new-submission item with a submission opens that submission', () {
    final d = NotificationRouter.resolve(
      item(
        actionType: 'submissions',
        ref: {'submissionId': 's7', 'tstruct': 'expense'},
      ),
    );
    expect(d, const Destination.submission('s7', 'expense'));
  });

  test('tickets and submissions without a submission id open the list', () {
    expect(
      kind(item(actionType: 'tickets', ref: {'tstruct': 'leave'})),
      DestinationKind.tickets,
    );
    expect(
      kind(item(actionType: 'submissions', ref: {'submissionId': ''})),
      DestinationKind.submissions,
    );
  });

  test('a submission item without a tstruct still opens the submission', () {
    final d = NotificationRouter.resolve(
      item(actionType: 'submissions', ref: {'submissionId': 5}),
    );
    expect(d.kind, DestinationKind.submission);
    expect(d.tstruct, isNull);
  });

  test('a to-do item (title and message only) is not detected as a task', () {
    expect(kind(const FeedItem(id: 'task:12')), DestinationKind.none);
    expect(kind(item(ref: {'taskId': 't1'})), DestinationKind.none);
    expect(
      kind(const FeedItem(id: '9', category: 'system', icon: 'task_alt')),
      DestinationKind.none,
    );
  });

  test('a task event destination carries the task id', () {
    const d = Destination.task(7);
    expect(d.kind, DestinationKind.task);
    expect(d.taskId, 7);
    expect(d.hasAction, isTrue);
  });

  test('none and a missing action have no button', () {
    expect(kind(item(actionType: 'none')), DestinationKind.none);
    expect(kind(item()), DestinationKind.none);
    expect(NotificationRouter.resolve(item()).hasAction, isFalse);
  });

  test('admin_console, about_me, axpert, smart_prompt, unknown: detail', () {
    for (final a in [
      'admin_console',
      'about_me',
      'axpert',
      'smart_prompt',
      'something_new',
    ]) {
      expect(kind(item(actionType: a)), DestinationKind.detail, reason: a);
    }
  });

  test('a push payload resolves the same way', () {
    expect(
      NotificationRouter.resolvePayload(
        const PushPayload(actionType: 'open_chat', chatId: 'user-sam1'),
      ),
      const Destination(DestinationKind.chat, conversationId: 'dm:sam1'),
    );
    expect(
      NotificationRouter.resolvePayload(
        const PushPayload(
          actionType: 'open_message',
          chatId: 'room-g',
          messageId: '5',
        ),
      ),
      const Destination(
        DestinationKind.message,
        conversationId: 'group:g',
        messageId: '5',
      ),
    );
    expect(
      NotificationRouter.resolvePayload(
        const PushPayload(actionType: 'approvals'),
      ).kind,
      DestinationKind.approvals,
    );
    expect(
      NotificationRouter.resolvePayload(const PushPayload(itemId: 'x')).kind,
      DestinationKind.detail,
    );
  });

  test('a ticket item opens the ticket by its submission id', () {
    final d = NotificationRouter.resolve(
      item(
        actionType: 'tickets',
        ref: {'submissionId': 38, 'tstruct': 'help_ticket'},
      ),
    );
    expect(d.kind, DestinationKind.ticket);
    expect(NotificationRouter.ticketIdOf(d), 38);
  });

  test('a ticket destination without a numeric id has no ticket to open', () {
    expect(
      NotificationRouter.ticketIdOf(const Destination.ticket('abc', null)),
      isNull,
    );
    expect(
      NotificationRouter.ticketIdOf(const Destination(DestinationKind.tickets)),
      isNull,
    );
  });

  test('a submissions item with a ref is not opened as a ticket', () {
    final d = NotificationRouter.resolve(
      item(actionType: 'submissions', ref: {'submissionId': 5}),
    );
    expect(d.kind, DestinationKind.submission);
    expect(NotificationRouter.ticketIdOf(d), isNull);
  });
}
