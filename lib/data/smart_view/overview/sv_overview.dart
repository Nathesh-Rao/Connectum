import '../models/sv_row.dart';
import '../models/sv_source.dart';

/// One status in a structure's mix: its label and how many records have it.
class SvStatusCount {
  const SvStatusCount(this.label, this.count);

  final String label;
  final int count;
}

/// What one overview card shows for one structure, worked out from the
/// records that were read (the newest page). Hidden fields are never read:
/// only the time, the approval state and the structure's own status field
/// (which is in the source list, so never hidden) are used.
class SvOverviewStats {
  const SvOverviewStats({
    required this.count,
    required this.loaded,
    required this.weekCount,
    required this.pendingCount,
    required this.buckets,
    required this.mix,
    required this.lastTs,
  });

  /// Records the server says exist (`total`), never less than [loaded].
  final int count;

  /// Records the stats were worked out from.
  final int loaded;

  /// Records submitted this week (Monday to now, device zone).
  final int weekCount;

  /// Loaded records waiting for approval.
  final int pendingCount;

  /// Records per day, the last seven days, today last.
  final List<int> buckets;

  /// Statuses, biggest first.
  final List<SvStatusCount> mix;

  /// The newest record's time, or null when there is none.
  final int? lastTs;

  /// Not every record was read, so week, mix and pending are of the newest.
  bool get isPartial => count > loaded;
}

/// The overview's numbers as pure functions of the rows and a clock.
class SvOverview {
  SvOverview._();

  static const days = 7;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Midnight (device zone) of the Monday of [now]'s week: the web's
  /// "This week" preset.
  static DateTime weekStart(DateTime now) {
    final today = _day(now);
    return DateTime(today.year, today.month, today.day - (today.weekday - 1));
  }

  /// Records with a time from Monday 00:00 to [now].
  static int weekCount(Iterable<SvRow> rows, DateTime now) {
    final from = weekStart(now).millisecondsSinceEpoch;
    final to = now.millisecondsSinceEpoch;
    var n = 0;
    for (final r in rows) {
      if (r.ts >= from && r.ts <= to) n++;
    }
    return n;
  }

  /// Seven buckets, one per local day, the last one today. A record in the
  /// future or older than six days ago is in none.
  static List<int> buckets(Iterable<SvRow> rows, DateTime now) {
    final today = _day(now);
    final starts = [
      for (var i = 0; i < days; i++)
        DateTime(
          today.year,
          today.month,
          today.day - (days - 1 - i),
        ).millisecondsSinceEpoch,
    ];
    final end = DateTime(
      today.year,
      today.month,
      today.day + 1,
    ).millisecondsSinceEpoch;
    final out = List<int>.filled(days, 0);
    for (final r in rows) {
      if (r.ts < starts.first || r.ts >= end) continue;
      for (var i = days - 1; i >= 0; i--) {
        if (r.ts >= starts[i]) {
          out[i]++;
          break;
        }
      }
    }
    return out;
  }

  /// The status of one record: the structure's status field when it has one
  /// (a value that is not in the source list counts as none), else the
  /// approval word (`Recorded`, `Waiting for approval`, ...).
  static String statusOf(SvSource source, SvRow row) {
    final field = source.table?.field;
    if (field != null && source.fieldOf(field) != null) {
      final raw = row.values[field];
      final label = row.labels[field];
      final text = '${label ?? raw ?? ''}'.trim();
      if (text.isNotEmpty) return text;
    }
    return row.approval;
  }

  /// Status counts, biggest first, ties by label.
  static List<SvStatusCount> statusMix(SvSource source, Iterable<SvRow> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      final s = statusOf(source, r);
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final out = [for (final e in counts.entries) SvStatusCount(e.key, e.value)];
    out.sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.label.compareTo(b.label);
    });
    return out;
  }

  static int pendingCount(Iterable<SvRow> rows) =>
      rows.where((r) => r.recordStatus.toLowerCase() == 'pending').length;

  /// The newest time among [rows], or null.
  static int? lastTs(Iterable<SvRow> rows) {
    int? best;
    for (final r in rows) {
      if (r.ts > 0 && (best == null || r.ts > best)) best = r.ts;
    }
    return best;
  }

  static SvOverviewStats stats(
    SvSource source,
    List<SvRow> rows, {
    required int total,
    required DateTime now,
  }) => SvOverviewStats(
    count: total < rows.length ? rows.length : total,
    loaded: rows.length,
    weekCount: weekCount(rows, now),
    pendingCount: pendingCount(rows),
    buckets: buckets(rows, now),
    mix: statusMix(source, rows),
    lastTs: lastTs(rows),
  );

  /// "just now", "5 min ago", "31 h ago" (up to three days), "5 d ago",
  /// "3 mo ago".
  static String age(int ts, DateTime now) {
    final diff = now.millisecondsSinceEpoch - ts;
    if (diff < 60 * 1000) return 'just now';
    final min = diff ~/ 60000;
    if (min < 60) return '$min min ago';
    final h = min ~/ 60;
    if (h < 72) return '$h h ago';
    final d = h ~/ 24;
    if (d < 60) return '$d d ago';
    return '${d ~/ 30} mo ago';
  }

  /// The card's footer.
  static String lastEntry(int? ts, DateTime now) =>
      ts == null ? 'No records yet' : 'Last entry ${age(ts, now)}';

  /// 12345 -> "12,345" (no intl).
  static String thousands(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// What one structure's read gave: the records (newest page), the server's
/// total and how it ended.
class SvOverviewRead {
  const SvOverviewRead({
    required this.isOk,
    this.rows = const [],
    this.total = 0,
  });

  final bool isOk;
  final List<SvRow> rows;
  final int total;
}
