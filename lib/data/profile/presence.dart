/// The manual presence a person sets for themselves, kept apart from their
/// status message. The wire words are exactly these five, lower case.
enum Presence {
  available('available', 'Available'),
  busy('busy', 'Busy'),
  meeting('meeting', 'In a meeting'),
  away('away', 'Away'),
  dnd('dnd', 'Do not disturb');

  const Presence(this.wire, this.label);

  final String wire;
  final String label;

  /// The value of a `profile` event's `presence`: one of the five words, else
  /// null (never chosen, or something this app does not know).
  static Presence? parse(Object? raw) {
    if (raw is! String) return null;
    for (final p in values) {
      if (p.wire == raw) return p;
    }
    return null;
  }

  /// What a status text says, for people who never chose a presence. Used for
  /// display only and never sent back (web `presenceTone`).
  static Presence derive(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (s.isEmpty) return available;
    if (s.contains('do not disturb') || s == 'dnd') return dnd;
    if (s.contains('meeting')) return meeting;
    if (s.contains('busy')) return busy;
    if (s.contains('away') || s.contains('offline')) return away;
    return available;
  }

  /// The one rule for what a person shows: the chosen value, else the status
  /// text's reading.
  static Presence of(Presence? chosen, String? status) =>
      chosen ?? derive(status);
}
