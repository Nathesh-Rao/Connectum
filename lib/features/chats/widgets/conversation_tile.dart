import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/attachment_tag.dart';
import '../../../core/utils/avatar_palette.dart';
import '../../../core/utils/forwarded_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/conversation_avatar.dart';
import '../../../core/widgets/app_row_highlight.dart';
import '../../../core/widgets/app_unread_badge.dart';
import '../../../data/models/conversation.dart';
import '../../../data/models/message.dart';
import '../chats_controller.dart';

/// One conversation row. Only the parts that change on their own sit in their
/// own Obx: the presence dot and the time label.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.controller,
    required this.onTap,
    this.onLongPress,
  });

  final Conversation conversation;
  final ChatsController controller;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static String typeLabel(String kind) => switch (kind) {
    'dm' => 'Direct message',
    'group' => 'Group',
    'host' => 'Team',
    _ => 'Everyone',
  };

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final hasUnread = c.unread > 0;
    final tone = AvatarPalette.indexOf(c.title) < 0
        ? AppColors.accent
        : AvatarPalette.fromName(c.title).foreground;
    return Semantics(
      button: true,
      label:
          '${c.title}, ${ConversationTile.typeLabel(c.kind)}${c.isPinned ? ', pinned' : ''}${c.isMuted ? ', muted' : ''}${hasUnread ? ', ${c.unreadLabel} unread' : ''}',
      excludeSemantics: true,
      child: AppRowHighlight(
        onTap: onTap,
        onLongPress: onLongPress,
        resetKey: Object.hash(c.isPinned, c.isMuted, c.lastTs),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.chatRowHeight,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(conversation: c, controller: controller),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.rowTitle.copyWith(
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (c.isPinned) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          const Icon(
                            Icons.push_pin,
                            size: 13,
                            color: AppColors.muted,
                          ),
                        ],
                        if (c.isMuted) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          const Icon(
                            Icons.volume_off,
                            size: 13,
                            color: AppColors.muted,
                          ),
                        ],
                        const SizedBox(width: AppSpacing.xs),
                        Obx(
                          () => Text(
                            RelativeTime.label(
                              c.lastTs,
                              controller.minute.value,
                            ),
                            style: AppText.caption.copyWith(
                              color: hasUnread && !c.isMuted
                                  ? tone
                                  : AppColors.muted,
                              fontWeight: hasUnread && !c.isMuted
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: _Preview(conversation: c)),
                        if (hasUnread) ...[
                          const SizedBox(width: AppSpacing.xs),
                          AppUnreadBadge(
                            label: c.unreadLabel,
                            isMuted: c.isMuted,
                            color: tone,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      ConversationTile.typeLabel(c.kind),
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.conversation, required this.controller});

  final Conversation conversation;
  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    if (c.kind != 'dm') return conversationAvatarFor(c);
    return Obx(
      () => conversationAvatarFor(c, presence: controller.presenceFor(c)),
    );
  }
}

/// The one-line preview. Mine starts with "You: ", a group message with the
/// sender. A form shows its name, even in an encrypted thread (forms are
/// never encrypted), an encrypted message that cannot be read a lock, a pending message a clock and a failed one an error mark.
class _Preview extends StatelessWidget {
  const _Preview({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final status = c.lastIsMine ? c.lastStatus : null;
    final icon = status == MessageStatus.failed
        ? const _Glyph(Icons.error_outline, AppColors.error)
        : status == MessageStatus.pending || status == MessageStatus.sending
        ? const _Glyph(Icons.schedule, AppColors.muted)
        : c.lastKind == 'form'
        ? const _Glyph(Icons.description_outlined, AppColors.muted)
        : c.lastIsEncrypted
        ? const _Glyph(Icons.lock_outline, AppColors.muted)
        : null;
    return Row(
      children: [
        if (icon != null) ...[icon, const SizedBox(width: AppSpacing.xxs)],
        Expanded(
          child: Text(
            _text(c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.rowCaption,
          ),
        ),
      ],
    );
  }

  static String _text(Conversation c) {
    if (c.lastIsDeleted) return 'Message deleted';
    if (c.lastKind == 'form') return '${c.lastFormName ?? 'Form'} submitted';
    if (c.lastIsEncrypted) return 'Encrypted message';
    final prefix = c.lastIsMine
        ? 'You: '
        : c.kind == 'group' && c.lastFrom.isNotEmpty
        ? '${c.lastFrom}: '
        : '';
    final text = ForwardedText.parse(c.lastText).text;
    return '$prefix${AttachmentTag.preview(text) ?? text}';
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: 13, color: color);
}
