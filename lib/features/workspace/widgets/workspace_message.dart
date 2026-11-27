import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/attachment_tag.dart';
import '../../../core/utils/mention_text.dart';
import '../../../data/models/message.dart';
import '../../conversation/models/chat_item.dart';
import '../../conversation/widgets/message_bubble.dart';

/// A note of mine in My Work Space: the chat's own bubble, on the right. A
/// note this phone cannot open shows the same locked line as in a chat.
class WorkspaceMessage extends StatelessWidget {
  const WorkspaceMessage({
    super.key,
    required this.message,
    required this.original,
    required this.me,
    this.onRetry,
    this.onLongPress,
    this.onSetUpEncryption,
    this.isHighlighted = false,
    this.isSaved = false,
    this.isPinned = false,
  });

  final Message message;
  final Message? original;
  final String me;
  final VoidCallback? onRetry;
  final VoidCallback? onLongPress;
  final VoidCallback? onSetUpEncryption;
  final bool isHighlighted;
  final bool isSaved;
  final bool isPinned;

  @override
  Widget build(BuildContext context) => MessageBubble(
    item: ChatItem.message(message),
    isDirect: false,
    isHighlighted: isHighlighted,
    isSaved: isSaved,
    isPinned: isPinned,
    original: original,
    onLongPress: onLongPress ?? () {},
    onRetry: onRetry ?? () {},
    reactions: const [],
    onReact: (_) {},
    attachmentOf: (tag) => _FileRow(tag: tag),
    people: MentionPeople(me: me.toLowerCase()),
    onReviewKey: () {},
    onSetUpEncryption: onSetUpEncryption,
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.tag});

  final AttachmentTag tag;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.attach_file, size: 16, color: AppColors.muted),
      const SizedBox(width: AppSpacing.xxs),
      Flexible(child: Text(tag.name, style: AppText.chatMessage)),
    ],
  );
}
