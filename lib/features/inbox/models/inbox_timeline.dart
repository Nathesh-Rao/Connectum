import 'inbox_row.dart';

/// The records of one day under their heading (Timeline).
class InboxDay {
  const InboxDay(this.heading, this.rows);

  final String heading;
  final List<InboxRow> rows;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Timeline: the loaded rows grouped by the person's local day of the record's
/// time (`dayHeading` in the web's `inboxFilters.js`). Newest day first; rows
/// keep the order they came in inside a day. Rows with no time are last,
/// under "No date". [now] is passed in so a test needs no clock.
class InboxTimeline {
  InboxTimeline._();

  static const noDate = 'No date';

  /// "Today", "Yesterday", or "Nov 17, 2026" for the day of [ts] (epoch ms) as
  /// seen from [now], both in local time.
  static String headingOf(int ts, DateTime now) {
    if (ts <= 0) return noDate;
    final at = DateTime.fromMillisecondsSinceEpoch(ts);
    final diff = _dayNumber(now) - _dayNumber(at);
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_months[at.month - 1]} ${at.day}, ${at.year}';
  }

  /// A count of calendar days that a change of clock cannot skew.
  static int _dayNumber(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

  static List<InboxDay> group(List<InboxRow> rows, DateTime now) {
    final byDay = <int, List<InboxRow>>{};
    final undated = <InboxRow>[];
    for (final r in rows) {
      if (r.ts <= 0) {
        undated.add(r);
        continue;
      }
      final at = DateTime.fromMillisecondsSinceEpoch(r.ts);
      byDay.putIfAbsent(_dayNumber(at), () => []).add(r);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final d in days)
        InboxDay(headingOf(byDay[d]!.first.ts, now), byDay[d]!),
      if (undated.isNotEmpty) InboxDay(noDate, undated),
    ];
  }
}
