/// One first-run tour. Bump [version] to show a tour again to everyone.
enum TourId {
  chatList(2),
  chat(2),
  workspace(2),
  commands(1),
  smartView(2),
  inbox(2),
  notifications(1),
  profile(2);

  const TourId(this.version);

  final int version;
}
