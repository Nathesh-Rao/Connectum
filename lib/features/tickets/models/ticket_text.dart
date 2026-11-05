import '../../../core/utils/chat_time.dart';
import '../../../data/models/ids.dart';

/// Words for the data of a ticket. Pure.
class TicketText {
  TicketText._();

  /// A record value as plain text: lists joined, yes/no for booleans, a map
  /// by its name or label. Never throws on an unknown shape.
  static String value(Object? v) {
    if (v == null) return '';
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is num) {
      return v is double && v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    }
    if (v is List) {
      return [
        for (final x in v)
          if (value(x).isNotEmpty) value(x),
      ].join(', ');
    }
    if (v is Map) {
      for (final key in const ['label', 'name', 'caption', 'value', 'id']) {
        final text = value(v[key]);
        if (text.isNotEmpty) return text;
      }
      return [
        for (final e in v.entries)
          if (value(e.value).isNotEmpty) '${idText(e.key)}: ${value(e.value)}',
      ].join(', ');
    }
    return idText(v).trim();
  }

  /// "just now", "5 min ago", "3 h ago", then the day.
  static String ago(int ts, DateTime now) {
    if (ts <= 0) return '';
    final diff = now.millisecondsSinceEpoch - ts;
    if (diff < 60 * 1000) return 'just now';
    if (diff < 60 * 60 * 1000) return '${diff ~/ 60000} min ago';
    if (diff < 24 * 60 * 60 * 1000 &&
        ChatTime.isSameDay(ts, now.millisecondsSinceEpoch)) {
      return '${diff ~/ 3600000} h ago';
    }
    return ChatTime.day(ts, now);
  }
}
