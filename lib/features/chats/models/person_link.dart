/// How the signed-in person stands with someone in the New chat list.
enum PersonLink {
  /// Not connected and nothing pending: the row offers Connect.
  none,

  /// I sent a connection request and it waits for their answer.
  requested,

  /// They sent me a request; I answer it from the Inbox.
  asked,

  /// Connected: the row opens the chat.
  connected,
}
