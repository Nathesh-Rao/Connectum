import 'package:get/get.dart';

import '../data/repositories/e2e_repository.dart';
import '../data/repositories/feed_repository.dart';
import '../data/session_store.dart';
import '../data/socket/socket_service.dart';
import '../features/notifications/models/feed_item.dart';

/// The notifications of the demo: every category, unread and read, three
/// priorities and one resolved. Reads, resolves and dismissals change this
/// list only.
class DemoFeedRepository extends FeedRepository {
  // ignore: use_super_parameters
  DemoFeedRepository(
    SocketService socket,
    SessionStore store,
    E2eRepository e2e,
  ) : _store = store,
      super(socket, store, e2e);

  final SessionStore _store;

  @override
  void onInit() {
    super.onInit();
    ever(_store.current, (session) {
      if (session != null) scheduleRefresh();
    });
  }

  @override
  Future<void> refresh() async {
    if (_store.current.value == null) return;
    if (items.isEmpty) items.assignAll(_build());
    _recount();
    isLoading.value = false;
    hasError.value = false;
  }

  @override
  Future<void> ensureFilter(String priority, bool isUnreadOnly) async {}

  @override
  Future<void> loadMore(String priority, bool isUnreadOnly) async {}

  void _recount() {
    final open = items.where((i) => !i.isResolved);
    counts.value = FeedCounts(
      high: open.where((i) => i.priority == 'high').length,
      medium: open.where((i) => i.priority == 'medium').length,
      low: open.where((i) => i.priority == 'low').length,
      resolved: items.where((i) => i.isResolved).length,
      unread: open.where((i) => !i.isRead).length,
      total: items.length,
    );
  }

  static List<FeedItem> _build() {
    final now = DateTime.now().millisecondsSinceEpoch;
    int ago(Duration d) => now - d.inMilliseconds;
    return [
      FeedItem(
        id: 'demo-1',
        priority: 'high',
        category: 'approvals',
        icon: 'approvals',
        actionType: 'approvals',
        actionLabel: 'Review',
        title: 'Approval needed',
        message: 'Emma Employee submitted an expense claim of ₹12,000.',
        ts: ago(const Duration(minutes: 4)),
      ),
      FeedItem(
        id: 'demo-2',
        priority: 'high',
        category: 'security',
        icon: 'security',
        actionType: 'about_me',
        title: 'New sign-in to your account',
        message: 'Moto g32 in Chennai signed in a moment ago.',
        ts: ago(const Duration(minutes: 11)),
      ),
      FeedItem(
        id: 'demo-3',
        priority: 'medium',
        category: 'tickets',
        icon: 'tickets',
        actionType: 'tickets',
        actionLabel: 'Open ticket',
        title: 'Ticket assigned to you',
        message: 'Printer jams on floor 2, raised by Ana.',
        ts: ago(const Duration(minutes: 35)),
      ),
      FeedItem(
        id: 'demo-4',
        priority: 'medium',
        category: 'tasks',
        icon: 'tasks',
        actionType: 'tasks',
        actionLabel: 'View tasks',
        title: 'Task due today',
        message: 'Send the Q4 expense report is due today.',
        ts: ago(const Duration(hours: 1)),
      ),
      FeedItem(
        id: 'demo-5',
        priority: 'medium',
        category: 'messages',
        icon: 'chat',
        actionType: 'open_chat',
        actionLabel: 'Open chat',
        chatId: 'user-priya',
        from: 'priya',
        title: 'Priya Sharma',
        message: "The new flow looks great. Let's ship it!",
        ts: ago(const Duration(hours: 2)),
      ),
      FeedItem(
        id: 'demo-6',
        priority: 'low',
        category: 'messages',
        icon: 'mention',
        actionType: 'open_chat',
        actionLabel: 'Open chat',
        chatId: 'room-Design Collective',
        title: 'Nina mentioned you',
        message: '@alex can you share the final component sheet?',
        ts: ago(const Duration(hours: 3)),
        isRead: true,
      ),
      FeedItem(
        id: 'demo-7',
        priority: 'low',
        category: 'reminders',
        icon: 'reminder',
        title: 'Reminder: vendor contract',
        message: 'The vendor contract review closes tomorrow at 5 pm.',
        ts: ago(const Duration(hours: 5)),
      ),
      FeedItem(
        id: 'demo-8',
        priority: 'low',
        category: 'broadcast',
        icon: 'broadcast',
        title: 'Announcement',
        message: 'The office is closed on Friday for the annual day.',
        ts: ago(const Duration(hours: 20)),
        isRead: true,
      ),
      FeedItem(
        id: 'demo-9',
        priority: 'resolved',
        category: 'approvals',
        icon: 'approvals',
        title: 'Leave request approved',
        message: 'Meg approved your leave request for 3 days.',
        ts: ago(const Duration(days: 1)),
        isRead: true,
        isResolved: true,
        resolvedTs: ago(const Duration(hours: 22)),
      ),
    ];
  }
}
