/// Times and day labels inside a conversation: "10:24 AM", "Today",
/// "Yesterday", a weekday, a date. Display only; the server ts is shown
/// against the phone's clock.
class ChatTime {
  ChatTime._();

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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

  static String time(int ts, {bool is24Hour = false}) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    if (is24Hour) {
      return '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static String date(int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${t.day} ${_months[t.month - 1]} ${t.year}';
  }

  static bool isSameDay(int a, int b) {
    final x = DateTime.fromMillisecondsSinceEpoch(a);
    final y = DateTime.fromMillisecondsSinceEpoch(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  static String day(int ts, DateTime now) {
    final then = DateTime.fromMillisecondsSinceEpoch(ts);
    final today = DateTime(now.year, now.month, now.day);
    final thenDay = DateTime(then.year, then.month, then.day);
    final days = today.difference(thenDay).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days > 1 && days < 7) return _weekdays[then.weekday - 1];
    final date = '${then.day} ${_months[then.month - 1]}';
    return then.year == now.year ? date : '$date ${then.year}';
  }
}
