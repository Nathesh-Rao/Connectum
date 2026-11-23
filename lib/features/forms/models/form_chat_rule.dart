import '../../../data/models/chat_thread.dart';
import '../../../data/repositories/conversation_repository.dart';

enum FormChatMode { none, always }

/// Whether a form opened from a conversation is posted into it. A shared
/// thread (`care-*`, `rec-*`) always posts; a direct chat, host, global, the
/// workspace and a team group never do (team group: pending BE doc), so the
/// record lives only in My Work Space.
class FormChatRule {
  FormChatRule._();

  /// After a save from a chat where nothing is posted, My Work Space opens
  /// (web `returnsToWorkspace`). Flip here if BE/web says otherwise.
  static const bool opensWorkspaceWhenNotPosted = true;

  static FormChatMode decide(String? convId) {
    if (convId == null) return FormChatMode.none;
    if (ConversationRepository.kindOf(convId) != 'group') {
      return FormChatMode.none;
    }
    final name = ChatThread.groupName(convId);
    return name != null && ChatThread.isThreadName(name)
        ? FormChatMode.always
        : FormChatMode.none;
  }

  /// The `chat` argument of a save: only a shared thread's own id.
  static String? chatFor(String? convId) =>
      decide(convId) == FormChatMode.always ? convId : null;

  /// A save from a direct chat or a team group opens My Work Space.
  static bool returnsToWorkspace(String? convId) {
    if (convId == null || !opensWorkspaceWhenNotPosted) return false;
    final kind = ConversationRepository.kindOf(convId);
    return (kind == 'dm' || kind == 'group') &&
        decide(convId) == FormChatMode.none;
  }
}
