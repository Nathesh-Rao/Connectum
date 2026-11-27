/// The sample data of one tour. Sample data lives in state of its own that
/// only the screen's view reads while the demo is on: never in SQLite, a
/// repository, the socket, the outbox, a count or a cursor.
class TourDemo {
  const TourDemo({required this.seed, required this.restore});

  /// Puts the sample in and returns true, or returns false when the screen
  /// already has real items to point at (real data first).
  final bool Function() seed;

  /// Takes the sample out and puts every UI state back. Must be safe to call
  /// when [seed] returned false, and more than once.
  final void Function() restore;
}
