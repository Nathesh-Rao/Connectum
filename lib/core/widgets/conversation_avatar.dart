import '../../data/models/chat_thread.dart';
import '../../data/models/conversation.dart';
import '../theme/app_spacing.dart';
import 'app_avatar.dart';

/// What the avatar of a conversation is drawn from. One rule for the chat
/// list, the conversation header and the info page, so they cannot drift.
class ConversationAvatarSpec {
  const ConversationAvatarSpec(this.name, this.kind);

  /// The palette seed and the letter: the conversation's title.
  final String name;
  final AppAvatarKind kind;

  static ConversationAvatarSpec of(Conversation c) {
    if (c.kind == 'dm') {
      return ConversationAvatarSpec(c.title, AppAvatarKind.person);
    }
    final groupName = ChatThread.groupName(c.convId);
    final isRecord = groupName != null && ChatThread.isRecordName(groupName);
    final isCare = groupName != null && ChatThread.careUser(groupName) != null;
    // A care thread is a person's: their name when the title has one.
    final hasPersonName = isCare && c.title.isNotEmpty && c.title != groupName;
    return ConversationAvatarSpec(
      c.title,
      hasPersonName
          ? AppAvatarKind.person
          : isRecord
          ? AppAvatarKind.ticket
          : AppAvatarKind.group,
    );
  }
}

/// The avatar of [c], the same in every place that shows one.
AppAvatar conversationAvatarFor(
  Conversation c, {
  double size = AppSpacing.avatar,
  AppPresenceDot presence = AppPresenceDot.none,
}) {
  final spec = ConversationAvatarSpec.of(c);
  return AppAvatar(
    name: spec.name,
    kind: spec.kind,
    picture: c.kind == 'dm' ? c.avatar : null,
    size: size,
    presence: presence,
  );
}
