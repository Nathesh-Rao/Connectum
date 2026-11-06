import '../../core/widgets/app_notices.dart';
import '../../data/repositories/feed_repository.dart';
import '../../data/socket/socket_service.dart';
import 'models/feed_item.dart';
import 'notification_texts.dart';

/// The writes on feed items, shared by the tile menu and the detail sheet:
/// optimistic in [FeedRepository] (rolled back on an error), told with
/// [AppNotices] here. Each returns whether it went through.
class FeedActions {
  FeedActions(this._feed);

  final FeedRepository _feed;

  Future<bool> setRead(FeedItem item, {required bool isRead}) =>
      run(() => _feed.setRead([item.id], isRead: isRead));

  Future<bool> resolve(FeedItem item) => run(() => _feed.resolve(item.id));

  Future<bool> dismiss(FeedItem item) => run(() => _feed.dismiss(item.id));

  Future<bool> run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on SocketCallError catch (e) {
      AppNotices.error(
        e.message.isNotEmpty ? e.message : NotificationTexts.actionFailed,
      );
      if (e.code == 'not_found') _feed.scheduleRefresh();
      return false;
    }
  }
}
