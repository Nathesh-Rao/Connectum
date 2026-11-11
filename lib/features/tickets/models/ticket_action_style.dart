import 'package:flutter/material.dart';

import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_action_bar.dart';
import '../../../data/models/ticket.dart';

/// The icon and tone of an action, picked from its words.
class ActionStyle {
  const ActionStyle(this.icon, this.tone);

  final IconData icon;
  final AppTone tone;
}

class _Rule {
  const _Rule(this.keywords, this.icon, this.tone);

  final List<String> keywords;
  final IconData icon;
  final AppTone tone;
}

/// The first rule with a keyword in the action's name wins, so a specific
/// word ("reassign") sits above the general one it contains ("assign").
const _rules = [
  _Rule(['reassign'], Icons.swap_horiz, AppTones.slate),
  _Rule(['reopen'], Icons.restart_alt, AppTones.blue),
  _Rule(['escalate'], Icons.trending_up, AppTones.orange),
  _Rule(['approve'], Icons.thumb_up_alt_outlined, AppTones.green),
  _Rule(['hold', 'pause'], Icons.pause_circle_outline, AppTones.slate),
  _Rule(
    ['complete', 'done', 'close', 'resolve'],
    Icons.check_circle_outline,
    AppTones.green,
  ),
  _Rule(['return', 'reject', 'revert'], Icons.undo, AppTones.orange),
  _Rule(
    ['drop', 'cancel', 'delete', 'withdraw'],
    Icons.remove_circle_outline,
    AppTones.red,
  ),
  _Rule(['send', 'assign', 'forward'], Icons.send_outlined, AppTones.blue),
  _Rule(['update'], Icons.published_with_changes, AppTones.slate),
];

const _fallback = ActionStyle(Icons.arrow_forward, AppTones.slate);

/// Icon and tone for an action called [name] (case does not matter).
ActionStyle actionStyleFor(String name) {
  final text = name.toLowerCase();
  for (final rule in _rules) {
    for (final keyword in rule.keywords) {
      if (text.contains(keyword)) return ActionStyle(rule.icon, rule.tone);
    }
  }
  return _fallback;
}

/// [actions] as bar items, in the same order.
List<ActionItem> actionItemsOf(List<TicketAction> actions) => [
  for (final a in actions)
    ActionItem(
      id: a.name,
      label: a.name,
      icon: actionStyleFor(a.name).icon,
      tone: actionStyleFor(a.name).tone,
    ),
];
