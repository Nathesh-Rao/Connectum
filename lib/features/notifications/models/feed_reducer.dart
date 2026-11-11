import 'feed_item.dart';

/// The list-side of the three feed events. Pure: every call returns a new
/// list and never changes the one it is given.
class FeedReducer {
  FeedReducer._();

  /// `feed_item`: add or replace by id, and put it first.
  static List<FeedItem> applyItem(List<FeedItem> list, FeedItem item) =>
      cap([item, ...list.where((i) => i.id != item.id)]);

  /// `feed_removed`.
  static List<FeedItem> applyRemoved(
    List<FeedItem> list,
    Iterable<String> ids,
  ) {
    final gone = ids.toSet();
    return list.where((i) => !gone.contains(i.id)).toList();
  }

  /// `feed_changed`: the read flag of these ids.
  static List<FeedItem> applyChanged(
    List<FeedItem> list,
    Iterable<String> ids, {
    required bool isRead,
  }) {
    final changed = ids.toSet();
    return [
      for (final i in list)
        changed.contains(i.id) ? i.copyWith(isRead: isRead) : i,
    ];
  }

  /// A fetched page folded into the list: the page wins by id, newest first.
  static List<FeedItem> merge(List<FeedItem> list, Iterable<FeedItem> page) {
    final byId = {for (final i in list) i.id: i};
    for (final i in page) {
      byId[i.id] = i;
    }
    final out = byId.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
    return cap(out);
  }

  /// A (re)connect read: the page is the whole list. Anything not in it was
  /// removed, resolved or dismissed elsewhere; there is no way to tell otherwise.
  static List<FeedItem> replace(Iterable<FeedItem> page) =>
      merge(const [], page);

  /// The newest [feedCap] items.
  static List<FeedItem> cap(List<FeedItem> list) =>
      list.length <= feedCap ? list : list.sublist(0, feedCap);

  /// What a filter chip shows. All is everything still open; resolved items
  /// have their own chip.
  static List<FeedItem> filter(
    List<FeedItem> list, {
    required String priority,
    required bool isUnreadOnly,
    Set<String> mutedConversations = const {},
  }) => filterAny(
    list,
    priorities: {priority},
    isUnreadOnly: isUnreadOnly,
    mutedConversations: mutedConversations,
  );

  /// What several chips show together: an item that matches any of them.
  static List<FeedItem> filterAny(
    List<FeedItem> list, {
    required Set<String> priorities,
    required bool isUnreadOnly,
    Set<String> mutedConversations = const {},
  }) => [
    for (final i in list)
      if (priorities.any((p) => matches(p, i)) &&
          (!isUnreadOnly || !i.isRead) &&
          !isMuted(i, mutedConversations))
        i,
  ];

  /// One chip: All is the open items, a priority chip is that priority (a
  /// resolved item has the priority `resolved`, so it only shows under
  /// Resolved).
  static bool matches(String priority, FeedItem item) =>
      priority == 'all' ? !item.isResolved : item.priority == priority;

  /// An item of a conversation the person muted stays out of the list. The
  /// server still creates it, so the client hides it.
  static bool isMuted(FeedItem item, Set<String> mutedConversations) {
    final chat = item.conversationId;
    return chat != null && mutedConversations.contains(chat);
  }
}
