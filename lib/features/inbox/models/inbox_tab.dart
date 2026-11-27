import 'package:flutter/material.dart';

/// One tab of the Inbox tab bar. A new tab is one more entry in [InboxTabs.all]
/// and one more page in the view.
class InboxTabDef {
  const InboxTabDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final InboxTab id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

enum InboxTab { records, approvals }

class InboxTabs {
  InboxTabs._();

  static const all = [
    InboxTabDef(
      id: InboxTab.records,
      label: 'Records',
      icon: Icons.inbox_outlined,
      selectedIcon: Icons.inbox_rounded,
    ),
    InboxTabDef(
      id: InboxTab.approvals,
      label: 'Approvals',
      icon: Icons.fact_check_outlined,
      selectedIcon: Icons.fact_check_rounded,
    ),
  ];

  static int indexOf(InboxTab t) => all.indexWhere((d) => d.id == t);
}
