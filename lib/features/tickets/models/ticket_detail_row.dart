import 'package:flutter/material.dart';

import '../../../core/theme/app_tones.dart';
import '../../../core/utils/chat_time.dart';

/// One line of the details list: its icon, label and a readable value.
class TicketDetailRow {
  const TicketDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.priority,
  });

  final IconData icon;
  final String label;
  final String value;

  /// The tone of a priority value; the row shows it as a pill.
  final AppTone? priority;

  static const _icons = [
    (['also tell', 'notify', 'cc'], Icons.groups_outlined),
    (['category'], Icons.category_outlined),
    (['expected', 'completion date'], Icons.event_available_outlined),
    (['need by', 'due', 'deadline'], Icons.event_outlined),
    (['priority'], Icons.flag_outlined),
    (['subtype', 'sub type', 'sub-type'], Icons.account_tree_outlined),
    (['ticket no', 'ticket number', 'number'], Icons.tag),
    (['raised by', 'assignee'], Icons.person_outline),
  ];

  static TicketDetailRow of(String label, String value) {
    final key = label.toLowerCase();
    var icon = Icons.notes;
    for (final (words, candidate) in _icons) {
      if (words.any(key.contains)) {
        icon = candidate;
        break;
      }
    }
    return TicketDetailRow(
      icon: icon,
      label: label,
      value: readable(value),
      priority: key.contains('priority') ? priorityTone(value) : null,
    );
  }

  static AppTone? priorityTone(String value) =>
      switch (value.trim().toLowerCase()) {
        'high' || 'urgent' || 'critical' => AppTones.red,
        'medium' || 'normal' => AppTones.violet,
        'low' => AppTones.slate,
        _ => null,
      };

  static final _iso = RegExp(r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}.*)?$');

  /// "2026-11-05" as "5 Nov 2026"; any other text as it is.
  static String readable(String value) {
    final text = value.trim();
    if (!_iso.hasMatch(text)) return value;
    final at = DateTime.tryParse(text);
    if (at == null) return value;
    final date = ChatTime.date(at.millisecondsSinceEpoch);
    return text.length > 10
        ? '$date, ${ChatTime.time(at.millisecondsSinceEpoch)}'
        : date;
  }
}
