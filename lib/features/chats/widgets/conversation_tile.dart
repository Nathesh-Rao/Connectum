import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_unread_badge.dart';
import '../../../data/models/conversation.dart';
import '../../../data/models/message.dart';
import '../chats_controller.dart';

/// One conversation row. Only the parts that change on their own sit in their
/// own Obx: the presence dot and the time label.
class ConversationTile extends StatefulWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.controller,
    required this.onTap,
  });

  final Conversation conversation;
  final ChatsController controller;
  final VoidCallback onTap;

  static String typeLabel(String kind) => switch (kind) {
    'dm' => 'Direct message',
    'group' => 'Group',
    'host' => 'Team',
    _ => 'Everyone',
  };

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final hasUnread = c.unread > 0;
    return Semantics(
      button: true,
      label:
          '${c.title}, ${ConversationTile.typeLabel(c.kind)}${hasUnread ? ', ${c.unread} unread' : ''}',
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) => setState(() => _isPressed = false),
        onPointerCancel: (_) => setState(() => _isPressed = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppCurves.out,
            constraints: const BoxConstraints(
              minHeight: AppSpacing.chatRowHeight,
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: _isPressed ? AppColors.accentTint : Colors.transparent,
              border: const Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Avatar(conversation: c, controller: widget.controller),
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
                          const SizedBox(width: AppSpacing.xs),
                          Obx(
                            () => Text(
                              RelativeTime.label(
                                c.lastTs,
                                widget.controller.minute.value,
                              ),
                              style: AppText.caption.copyWith(
                                color: hasUnread
                                    ? AppColors.accentInk
                                    : AppColors.muted,
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
                            AppUnreadBadge(count: c.unread),
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
    final isDirect = conversation.kind == 'dm';
    if (!isDirect) {
      return AppAvatar(name: conversation.title, isSquare: true);
    }
    return Obx(
      () => AppAvatar(
        name: conversation.title,
        presence: controller.presenceFor(conversation),
      ),
    );
  }
}

/// The one-line preview. Mine starts with "You: ", a group message with the
/// sender. A form shows its name, an encrypted message a lock (mobile cannot
/// read those in v1), a pending message a clock and a failed one an error mark.
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
        : c.lastIsEncrypted
        ? const _Glyph(Icons.lock_outline, AppColors.muted)
        : c.lastKind == 'form'
        ? const _Glyph(Icons.description_outlined, AppColors.muted)
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
    if (c.lastIsEncrypted) return 'Encrypted message';
    if (c.lastKind == 'form') return '${c.lastFormName ?? 'Form'} submitted';
    final prefix = c.lastIsMine
        ? 'You: '
        : c.kind == 'group' && c.lastFrom.isNotEmpty
        ? '${c.lastFrom}: '
        : '';
    return '$prefix${c.lastText}';
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(icon, size: 13, color: color);
}
