class ChatPerson {
  const ChatPerson({
    required this.username,
    required this.name,
    required this.source,
    this.canInteract,
  });

  final String username;
  final String name;

  /// `conversation`, `connection` or `search`.
  final String source;

  /// Only a search hit says whether the organisation's interaction rules
  /// allow talking to the person.
  final bool? canInteract;

  bool get isKnown => source != 'search';
}
