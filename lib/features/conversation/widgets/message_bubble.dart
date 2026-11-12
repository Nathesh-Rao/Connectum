import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/attachment_tag.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/utils/forwarded_text.dart';
import '../../../core/utils/mention_text.dart';
import '../../../core/widgets/app_mention_text.dart';
import '../../../data/e2e/e2e_texts.dart';
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
    required this.attachmentOf,
    required this.people,
    required this.onReviewKey,
    this.isHighlighted = false,
    this.onOpenOriginal,
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

  /// The picture or file row of an attachment message.
  final Widget Function(AttachmentTag tag) attachmentOf;

  /// Whose @tags are drawn as a name; any other tag stays as typed.
  final MentionPeople people;

  /// Flashes the bubble (it was just opened from a reply quote).
  final bool isHighlighted;

  /// Scrolls to the quoted message; null when the quote has no known id.
  final VoidCallback? onOpenOriginal;

  /// Opens the key review for a sender whose changed key hid the message.
  final VoidCallback onReviewKey;

  static Color _senderInk(String name) {
    var h = 0;
    for (final u in name.toLowerCase().codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return AppColors.senderInks[h % AppColors.senderInks.length];
  }

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
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.bubblePadX,
          vertical: AppSpacing.bubblePadY,
        ),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppColors.primaryTintStrong
              : isMine
              ? AppColors.bubbleOut
              : AppColors.bubbleIn,
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
                  style: AppText.label.copyWith(color: _senderInk(m.sender)),
                ),
              ),
            if (m.replyTo != null)
              _Quote(
                original: original,
                replyTo: m.replyTo!,
                people: people,
                onTap: original == null ? null : onOpenOriginal,
              ),
            _Body(
              message: m,
              attachmentOf: attachmentOf,
              people: people,
              onReviewKey: onReviewKey,
            ),
            const SizedBox(height: AppSpacing.xxs),
            if (failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  m.secureFailure == null
                      ? 'Not sent. Tap to retry'
                      : 'Not sent. ${m.secureFailure}. Tap to retry',
                  style: AppText.error,
                ),
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
                  Text(
                    '${ChatTime.time(m.ts, is24Hour: MediaQuery.alwaysUse24HourFormatOf(context))}'
                    '${m.editedTs == null ? '' : ' • edited'}',
                    style: AppText.caption,
                  ),
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
  const _Body({
    required this.message,
    required this.attachmentOf,
    required this.people,
    required this.onReviewKey,
  });

  final Message message;
  final Widget Function(AttachmentTag tag) attachmentOf;
  final MentionPeople people;
  final VoidCallback onReviewKey;

  @override
  Widget build(BuildContext context) {
    if (message.isEncryptedUnsupported) {
      if (!message.isDecrypting) {
        final text = Text(
          E2eTexts.unreadableFor(message.unreadableCode),
          style: AppText.message.copyWith(color: AppColors.muted),
        );
        return message.unreadableCode == 'key_changed'
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onReviewKey,
                child: text,
              )
            : text;
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              'Decrypting...',
              style: AppText.message.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    final forward = ForwardedText.parse(message.text, sender: message.sender);
    final tag = AttachmentTag.parse(forward.text);
    final body = tag == null
        ? AppMentionText(
            text: forward.text,
            style: AppText.message,
            people: people,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              attachmentOf(tag),
              if (tag.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(tag.caption, style: AppText.message),
                ),
            ],
          );
    if (!forward.isForwarded) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ForwardBanner(
          forwardedBy: forward.forwardedBy ?? message.sender,
          originalFrom: forward.originalFrom,
        ),
        body,
      ],
    );
  }
}

/// "Forwarded by `name`" above a forwarded message. The web shows only the
/// forwarder; the " • from `author`" part is a small addition of ours, kept
/// here so it is easy to remove. Drawn in [AppColors.primaryStrong], which reads
/// on both the incoming grey and the outgoing blue bubble. No side bar: that
/// belongs to the reply quote.
class ForwardBanner extends StatelessWidget {
  const ForwardBanner({
    super.key,
    required this.forwardedBy,
    required this.originalFrom,
  });

  final String forwardedBy;
  final String? originalFrom;

  @override
  Widget build(BuildContext context) {
    final from = originalFrom;
    final base = AppText.label.copyWith(
      fontSize: AppText.sizeReadable,
      color: AppColors.primaryStrong,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shortcut, size: 14, color: AppColors.primaryStrong),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text.rich(
              TextSpan(
                style: base,
                children: [
                  TextSpan(text: 'Forwarded by $forwardedBy'),
                  if (from != null) ...[
                    const TextSpan(text: ' • from '),
                    TextSpan(
                      text: from,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({
    required this.original,
    required this.replyTo,
    required this.people,
    required this.onTap,
  });

  final Message? original;
  final String replyTo;
  final MentionPeople people;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final o = original;
    final text = o == null
        ? 'Message #$replyTo'
        : o.isEncryptedUnsupported
        ? "Can't be read on this device"
        : AttachmentTag.preview(ForwardedText.parse(o.text).text) ??
              ForwardedText.parse(o.text).text;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xxs,
            AppSpacing.xs,
            AppSpacing.xxs,
          ),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.primaryBright, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                o == null ? 'Replied message' : o.sender,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: AppColors.primaryStrong),
              ),
              AppMentionText(
                text: text,
                style: AppText.caption,
                people: people,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
