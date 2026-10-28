class MessageHit {
  const MessageHit({
    required this.convId,
    required this.title,
    required this.snippet,
    required this.ts,
  });

  final String convId;
  final String title;
  final String snippet;
  final int ts;
}
