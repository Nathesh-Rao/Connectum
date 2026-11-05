import 'dart:async';

import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/routes/conversation_route.dart';
import '../../data/notifications/push/push_payload.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/repositories/task_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/socket/socket_service.dart';
import '../tasks/tasks_controller.dart';
import '../../data/models/ids.dart';
import '../../data/session_store.dart';
import 'models/feed_item.dart';
import 'widgets/feed_detail_sheet.dart';

enum DestinationKind {
  chat,
  message,
  approvals,
  tickets,
  ticket,
  submissions,
  submission,
  tasks,
  task,
  detail,
  none,
}

/// Where a notification leads. [item] is kept for the detail sheet.
class Destination {
  const Destination(
    this.kind, {
    this.conversationId,
    this.messageId,
    this.submissionId,
    this.tstruct,
    this.taskId,
    this.item,
  });

  /// One task, from a `task_assigned` / `task_updated` event.
  const Destination.task(int this.taskId)
    : kind = DestinationKind.task,
      conversationId = null,
      messageId = null,
      submissionId = null,
      tstruct = null,
      item = null;

  /// One ticket of a form (`tickets` item with `ref.submissionId`).
  const Destination.ticket(String this.submissionId, this.tstruct, {this.item})
    : kind = DestinationKind.ticket,
      conversationId = null,
      messageId = null,
      taskId = null;

  /// One submission (`submissions` item with `ref.submissionId`).
  const Destination.submission(
    String this.submissionId,
    this.tstruct, {
    this.item,
  }) : kind = DestinationKind.submission,
       conversationId = null,
       messageId = null,
       taskId = null;

  final DestinationKind kind;

  /// `dm:<user>` or `group:<name>`.
  final String? conversationId;
  final String? messageId;
  final String? submissionId;
  final String? tstruct;
  final int? taskId;
  final FeedItem? item;

  /// A button belongs on the tile.
  bool get hasAction => kind != DestinationKind.none;

  @override
  bool operator ==(Object other) =>
      other is Destination &&
      other.kind == kind &&
      other.conversationId == conversationId &&
      other.messageId == messageId &&
      other.submissionId == submissionId &&
      other.tstruct == tstruct &&
      other.taskId == taskId;

  @override
  int get hashCode => Object.hash(
    kind,
    conversationId,
    messageId,
    submissionId,
    tstruct,
    taskId,
  );
}

/// The one place that knows where a feed item, a local notification or a push
/// leads. [resolve] and [resolvePayload] are pure; [handle] opens the result,
/// or keeps it until the person is signed in and the home is up.
class NotificationRouter extends GetxService {
  NotificationRouter(this._store, this._feed, this._tasks, this._tickets);

  final SessionStore _store;
  final FeedRepository _feed;
  final TaskRepository _tasks;
  final TicketRepository _tickets;

  /// Set by the home shell: selects a tab of the home.
  void Function(int index)? selectTab;

  static const submissionsTab = 2;

  Destination? _pending;
  String? _pendingOwner;
  bool _isHomeReady = false;

  /// Destinations the person has already seen the detail of are not queued.
  Destination? get pending => _pending;

  static Destination resolve(FeedItem item) {
    final chat = item.conversationId;
    switch (item.actionType) {
      case 'open_chat':
        return chat == null
            ? Destination(DestinationKind.detail, item: item)
            : Destination(
                DestinationKind.chat,
                conversationId: chat,
                item: item,
              );
      case 'open_message':
        if (chat == null) {
          return Destination(DestinationKind.detail, item: item);
        }
        final id = item.messageId;
        return id == null
            ? Destination(
                DestinationKind.chat,
                conversationId: chat,
                item: item,
              )
            : Destination(
                DestinationKind.message,
                conversationId: chat,
                messageId: id,
                item: item,
              );
      case 'approvals':
        return Destination(DestinationKind.approvals, item: item);
      case 'tickets':
        final (id, tstruct) = _submissionOf(item);
        return id == null
            ? Destination(DestinationKind.tickets, item: item)
            : Destination.ticket(id, tstruct, item: item);
      case 'submissions':
        final (id, tstruct) = _submissionOf(item);
        return id == null
            ? Destination(DestinationKind.submissions, item: item)
            : Destination.submission(id, tstruct, item: item);
      case 'tasks' || 'task':
        return Destination(DestinationKind.tasks, item: item);
      case null || '' || 'none':
        // To-do items carry no ref and no action: nothing says which task.
        return Destination(DestinationKind.none, item: item);
      default:
        // admin_console, about_me, axpert, smart_prompt and anything new.
        return Destination(DestinationKind.detail, item: item);
    }
  }

  static (String?, String?) _submissionOf(FeedItem item) {
    final id = item.ref['submissionId'];
    final tstruct = item.ref['tstruct'];
    return (
      id == null || idText('$id').isEmpty ? null : idText('$id'),
      tstruct == null || '$tstruct'.isEmpty ? null : '$tstruct',
    );
  }

  static Destination resolvePayload(PushPayload payload) {
    final chat = FeedItem.conversationOfChatId(payload.chatId);
    switch (payload.actionType) {
      case 'open_chat':
        return chat == null
            ? const Destination(DestinationKind.none)
            : Destination(DestinationKind.chat, conversationId: chat);
      case 'open_message':
        if (chat == null) return const Destination(DestinationKind.none);
        final id = payload.messageId;
        return id == null
            ? Destination(DestinationKind.chat, conversationId: chat)
            : Destination(
                DestinationKind.message,
                conversationId: chat,
                messageId: id,
              );
      case 'approvals':
        return const Destination(DestinationKind.approvals);
      case 'tickets':
        return const Destination(DestinationKind.tickets);
      case 'submissions':
        return const Destination(DestinationKind.submissions);
      case 'tasks' || 'task':
        return const Destination(DestinationKind.tasks);
      default:
        // No item to show: the notifications list is the fallback.
        return const Destination(DestinationKind.detail);
    }
  }

  /// A notification was tapped, or an item button pressed.
  void handleItem(FeedItem item) => handle(resolve(item));

  void handlePayload(PushPayload payload) => handle(resolvePayload(payload));

  void handle(Destination destination) {
    if (destination.kind == DestinationKind.none) return;
    if (!_isHomeReady || !_store.hasEnterpriseSession) {
      _pending = destination;
      _pendingOwner = _owner;
      return;
    }
    _open(destination);
  }

  /// The home is up and the person is signed in: opens what was waiting.
  void markHomeReady() {
    _isHomeReady = true;
    final waiting = _pending;
    if (waiting == null || !_store.hasEnterpriseSession) return;
    _pending = null;
    if (_pendingOwner != null && _pendingOwner != _owner) return;
    scheduleMicrotask(() => _open(waiting));
  }

  /// Whose session was up when a target was kept; null while signed out.
  String? get _owner =>
      _store.hasEnterpriseSession ? '${_store.orgId}/${_store.userId}' : null;

  void markHomeGone() => _isHomeReady = false;

  void _open(Destination d) {
    switch (d.kind) {
      case DestinationKind.chat:
        ConversationRoute.open(d.conversationId!);
      case DestinationKind.message:
        ConversationRoute.jumpTo(d.conversationId!, d.messageId!);
        ConversationRoute.open(d.conversationId!);
      case DestinationKind.submissions:
        Get.until((r) => r.isFirst);
        selectTab?.call(submissionsTab);
      case DestinationKind.approvals:
        _openScreen(AppRoutes.approvals);
      case DestinationKind.tasks:
        _openScreen(AppRoutes.tasks);
      case DestinationKind.task:
        if (Get.currentRoute == AppRoutes.tasks) {
          _tasks.requestOpen(d.taskId!);
        } else {
          Get.toNamed(AppRoutes.tasks, arguments: d.taskId);
        }
      case DestinationKind.tickets:
        if (Get.currentRoute != AppRoutes.tasks) {
          Get.toNamed(AppRoutes.tasks, arguments: TasksController.showTickets);
        }
      case DestinationKind.ticket:
        unawaited(_openTicket(d));
      // TODO: open a submission itself when its screen takes a link; the
      // sheet meanwhile.
      case DestinationKind.submission:
      case DestinationKind.detail:
        final item = d.item;
        if (item == null) {
          _openList();
        } else {
          showDetail(item);
        }
      case DestinationKind.none:
    }
  }

  /// The ticket of a notification: read with `status.get`. A record that is
  /// not a ticket (no status table) falls back to the detail sheet. When the
  /// read fails the ticket screen opens anyway and says why, with a retry.
  Future<void> _openTicket(Destination d) async {
    final id = ticketIdOf(d);
    final item = d.item;
    if (id == null) {
      if (item == null) {
        _openList();
      } else {
        showDetail(item);
      }
      return;
    }
    try {
      final detail = await _tickets.get(id);
      if (!detail.ticket.isTicket) {
        if (item == null) {
          _openList();
        } else {
          showDetail(item);
        }
        return;
      }
    } on SocketCallError catch (e) {
      if (e.code == 'not_found') {
        AppNotices.info('That ticket is no longer available.');
        return;
      }
    }
    final route = AppRoutes.ticketOf(id);
    if (Get.currentRoute != route) Get.toNamed(route);
  }

  /// The ticket id of a ticket destination; null when it is not a number.
  static int? ticketIdOf(Destination d) =>
      d.kind == DestinationKind.ticket ? idNumber(d.submissionId) : null;

  /// The title and the whole message of an item, in a light sheet.
  void showDetail(FeedItem item) {
    final context = Get.context;
    if (context == null) return;
    FeedDetailSheet.show(context, item, _feed.readableText(item));
  }

  /// Tasks and Approvals open on their first tab. Already there: nothing to
  /// do, the screen refreshes itself.
  void _openScreen(String route) {
    if (Get.currentRoute != route) Get.toNamed(route);
  }

  void _openList() {
    if (Get.currentRoute != AppRoutes.notifications) {
      Get.toNamed(AppRoutes.notifications);
    }
  }
}
