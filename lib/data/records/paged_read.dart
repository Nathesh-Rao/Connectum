import '../../core/debug/records_log.dart';
import '../socket/socket_service.dart';

/// One page as the loop needs it: how many rows the reply held (readable or
/// not) and whether the server says there are more.
typedef PagedPage = ({int received, bool hasMore});

/// How a paged read ended.
class PagedResult {
  const PagedResult({
    required this.rows,
    required this.pages,
    this.error,
    this.isCapped = false,
  });

  /// Rows received, readable or not.
  final int rows;
  final int pages;

  /// The code of the failure that stopped the read, if any. A failed read is
  /// never an empty list: the caller keeps what it had.
  final String? error;

  /// The page limit was reached while the server had more.
  final bool isCapped;

  bool get isOk => error == null;
}

/// Reads a list page after page the way the web does: the next offset is the
/// offset plus the rows received (`next` is null for `records.mine` with and
/// involved, and a page can be short while `hasMore` is true), one page at a
/// time with [gap] between pages (the server allows 30 commands per 10 s).
/// The page limit and any failure are logged, never swallowed.
class PagedRead {
  PagedRead._();

  static Future<PagedResult> run({
    required String label,
    required Future<PagedPage> Function(int offset) page,
    required int maxPages,
    Duration gap = Duration.zero,
    bool Function()? isStale,
  }) async {
    var offset = 0;
    var pages = 0;
    while (pages < maxPages) {
      if (pages > 0 && gap > Duration.zero) await Future<void>.delayed(gap);
      if (isStale?.call() ?? false) {
        return PagedResult(rows: offset, pages: pages, error: 'stale');
      }
      final PagedPage got;
      try {
        got = await page(offset);
      } on SocketCallError catch (e) {
        RecordsLog.line(
          '$label failed at offset=$offset after $pages page(s): ${e.code}',
        );
        return PagedResult(rows: offset, pages: pages, error: e.code);
      }
      if (isStale?.call() ?? false) {
        return PagedResult(rows: offset, pages: pages, error: 'stale');
      }
      pages++;
      offset += got.received;
      if (!got.hasMore || got.received == 0) {
        return PagedResult(rows: offset, pages: pages);
      }
    }
    RecordsLog.line(
      '$label stopped at the $maxPages-page cap with $offset rows read; '
      'the server has more',
    );
    return PagedResult(rows: offset, pages: pages, isCapped: true);
  }
}
