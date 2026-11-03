/// Chat-list time labels: "now", "2m", "1h", "Yesterday", a weekday, a date.
/// The server ts is shown against the phone's clock; this is display only.
class RelativeTime {
  RelativeTime._();

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
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

  static String label(int ts, DateTime now) {
    if (ts <= 0) return '';
    final then = DateTime.fromMillisecondsSinceEpoch(ts);
    final diff = now.difference(then);
    if (diff.isNegative || diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    final today = DateTime(now.year, now.month, now.day);
    final thenDay = DateTime(then.year, then.month, then.day);
    final days = today.difference(thenDay).inDays;
    if (days == 0) return '${diff.inHours}h';
    if (days == 1) return 'Yesterday';
    if (days < 7) return _weekdays[then.weekday - 1];
    final date = '${then.day} ${_months[then.month - 1]}';
    return then.year == now.year ? date : '$date ${then.year}';
  }
}
