class ChatPerson {
  const ChatPerson({
    required this.username,
    required this.name,
    required this.source,
    this.canInteract,
    this.detail = '',
  });

  final String username;
  final String name;

  /// `conversation`, `connection`, `colleague` or `search`.
  final String source;

  /// Only a search hit says whether the organisation's interaction rules
  /// allow talking to the person.
  final bool? canInteract;

  /// Designation or department, when the list gives one.
  final String detail;

  bool get isKnown => source != 'search';
}
