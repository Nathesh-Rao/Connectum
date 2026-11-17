enum SmartViewEntryKind { tab, drawer, named }

/// How the Smart view tab is entered: from the tab itself, from `#view`
/// (drawer open, every view listed) or from `#view <name>` (that view loaded,
/// drawer closed).
class SmartViewEntry {
  const SmartViewEntry.tab() : kind = SmartViewEntryKind.tab, name = '';

  const SmartViewEntry.drawer() : kind = SmartViewEntryKind.drawer, name = '';

  const SmartViewEntry.named(this.name) : kind = SmartViewEntryKind.named;

  final SmartViewEntryKind kind;
  final String name;
}
