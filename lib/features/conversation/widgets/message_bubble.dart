import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/chat_time.dart';
import '../../../data/models/message.dart';
import '../../../data/models/reaction.dart';
import '../models/chat_item.dart';
import 'reaction_chips.dart';
import 'message_status_mark.dart';

/// One message: sent on the right, received on the left. The time and, on
/// mine, the status mark sit inside the bubble at the bottom right. A run from
/// the same sender is packed (the tail only on the last bubble); a received
/// name shows above the first bubble of a run in groups and teams.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.item,
    required this.isDirect,
    required this.original,
    required this.onLongPress,
    required this.onRetry,
    required this.reactions,
    required this.onReact,
  });

  static const _maxWidthFraction = 0.88;

  final ChatItem item;
  final bool isDirect;

  /// The message this one replies to, when it is cached.
  final Message? original;
  final VoidCallback onLongPress;
  final VoidCallback onRetry;
  final List<Reaction> reactions;
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final m = item.message!;
    final isMine = m.isMine;
    const radius = Radius.circular(AppRadius.bubble);
    const tail = Radius.circular(AppRadius.bubbleTail);
    final shape = BorderRadius.only(
      topLeft: radius,
      topRight: radius,
      bottomLeft: !isMine && item.isLastOfRun ? tail : radius,
      bottomRight: isMine && item.isLastOfRun ? tail : radius,
    );
    final failed = m.status == MessageStatus.failed;
    Widget bubble = GestureDetector(
      onTap: failed ? onRetry : null,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.bubblePadX,
          vertical: AppSpacing.bubblePadY,
        ),
        decoration: BoxDecoration(
          color: isMine ? AppColors.accentTint : AppColors.bubbleIn,
          borderRadius: shape,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.showName)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  m.sender,
                  style: AppText.label.copyWith(color: AppColors.accentInk),
                ),
              ),
            if (m.replyTo != null && !m.isDeleted) _Quote(original: original),
            _Body(message: m),
            const SizedBox(height: AppSpacing.xxs),
            if (failed)
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text('Not sent. Tap to retry', style: AppText.error),
              ),
            Align(
              alignment: Alignment.centerRight,
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.isEncrypted && !m.isEncryptedUnsupported) ...[
                    const Icon(
                      Icons.lock,
                      size: AppSpacing.statusIcon,
                      color: AppColors.yesText,
                      semanticLabel: 'End-to-end encrypted',
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Text(ChatTime.time(m.ts), style: AppText.caption),
                  if (isMine) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    MessageStatusMark(status: m.status, isDirect: isDirect),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (item.isFresh) bubble = _Entrance(child: bubble);
    return Padding(
      padding: EdgeInsets.only(
        top: item.isFirstOfRun ? AppSpacing.bubbleGap : AppSpacing.bubbleRunGap,
      ),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, box) => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: box.maxWidth * _maxWidthFraction,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                bubble,
                ReactionChips(reactions: reactions, onToggle: onReact),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return Text(
        'Message deleted',
        style: AppText.message.copyWith(
          fontStyle: FontStyle.italic,
          color: AppColors.muted,
        ),
      );
    }
    if (message.isEncryptedUnsupported) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              message.isDecrypting
                  ? 'Decrypting...'
                  : "This message can't be read on this device",
              style: AppText.message.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    return Text(message.text, style: AppText.message);
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.original});

  final Message? original;

  @override
  Widget build(BuildContext context) {
    final text = original == null
        ? 'Original message'
        : original!.isDeleted
        ? 'Message deleted'
        : original!.isEncryptedUnsupported
        ? "Can't be read on this device"
        : original!.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.xxs,
          AppSpacing.xs,
          AppSpacing.xxs,
        ),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.accent, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (original != null)
              Text(
                original!.sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: AppColors.accentInk),
              ),
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.base,
      curve: AppCurves.out,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, AppDistances.tab * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
