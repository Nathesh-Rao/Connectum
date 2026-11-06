import 'package:flutter/painting.dart';

import '../../core/theme/app_colors.dart';
import 'models/feed_item.dart';

/// The main words of a notification message, drawn bold in the primary
/// colour: the sender or group name, the device label, quoted names; and
/// `@name` tags in the mention style. Pure.
class FeedHighlight {
  FeedHighlight._();

  static const _tag = r'@[A-Za-z0-9][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)*';
  static const _quoted = '"[^"]+"|“[^”]+”';

  /// The device name of an item, when its `ref` carries one.
  static String? deviceLabel(FeedItem item) {
    for (final key in const ['deviceLabel', 'device', 'label']) {
      final v = item.ref[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// Names to emphasise: the title and sender of a message, its group, the
  /// device. Longest first so a longer name wins over one inside it.
  static List<String> names(FeedItem item) {
    final group = item.conversationId?.startsWith('group:') ?? false
        ? item.conversationId!.substring(6)
        : null;
    final all = <String>{
      if (item.category == 'messages' ||
          item.actionType == 'open_chat' ||
          item.actionType == 'open_message')
        item.title,
      ?item.from,
      ?group,
      ?deviceLabel(item),
    }..removeWhere((n) => n.trim().length < 2);
    return all.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  static List<InlineSpan> spans(
    String text,
    FeedItem item, {
    required TextStyle base,
  }) {
    final strong = base.copyWith(
      fontWeight: FontWeight.w700,
      color: AppColors.accent,
    );
    final tag = base.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.mention,
    );
    final alternatives = [
      '($_tag)',
      '($_quoted)',
      for (final n in names(item)) '(${RegExp.escape(n)})',
    ];
    final pattern = RegExp(alternatives.join('|'));
    final result = <InlineSpan>[];
    var at = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > at) result.add(TextSpan(text: text.substring(at, m.start)));
      result.add(
        TextSpan(text: m.group(0), style: m.group(1) != null ? tag : strong),
      );
      at = m.end;
    }
    if (at < text.length) result.add(TextSpan(text: text.substring(at)));
    return result;
  }
}
