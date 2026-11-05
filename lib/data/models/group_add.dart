import '../../features/chats/models/chat_person.dart';

enum GroupAddStatus { added, invited, failed }

/// What one `/addmember` came to. [reason] is the server's own text for a
/// failure.
class GroupAddResult {
  const GroupAddResult(this.person, this.status, [this.reason = '']);

  final ChatPerson person;
  final GroupAddStatus status;
  final String reason;
}

enum GroupCreateStatus { created, refused, unconfirmed, offline }

class GroupCreateResult {
  const GroupCreateResult(this.status, [this.text = '']);

  final GroupCreateStatus status;
  final String text;
}

/// One page of `users.colleagues`; [next] is the opaque cursor for `after`.
class GroupPeoplePage {
  const GroupPeoplePage(this.people, {this.hasMore = false, this.next});

  final List<ChatPerson> people;
  final bool hasMore;
  final String? next;
}
