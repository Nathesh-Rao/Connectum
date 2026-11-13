import '../ai_chat/ai_entry.dart';
import '../ai_chat/widgets/ai_header_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_form_card.dart';
import '../../core/widgets/conversation_avatar.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_skeleton.dart';
import '../../core/widgets/app_state_image.dart';
import 'conversation_controller.dart';
import 'models/chat_item.dart';
import 'widgets/ticket_card_actions.dart';
import 'widgets/attachment_view.dart';
import 'widgets/chat_rows.dart';
import 'widgets/conversation_composer.dart';
import 'widgets/conversation_header.dart';
import 'widgets/message_actions_sheet.dart';
import 'widgets/device_limit_banner.dart';
import 'widgets/key_change_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_status_mark.dart';
import 'widgets/reaction_chips.dart';
import '../tickets/tickets_texts.dart';
import 'widgets/scroll_to_latest_button.dart';
import 'widgets/typing_dots.dart';
import 'widgets/upload_bubble.dart';

/// The conversation screen. It takes its id from its own route and uses the
/// controller put under that id, so two conversations can be open at once.
class ConversationView extends GetView<ConversationController> {
  const ConversationView({super.key, required this.conversationId});

  final String conversationId;

  @override
  String? get tag => conversationId;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyChats,
      AppStateImageKind.locked,
    ], size: AppSpacing.stateImageSmall);
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Obx(() {
        // A home reload takes this screen down first, then closes its
        // controller: nothing below may be mounted by then.
        if (c.isRetired.value) return const SizedBox.shrink();
        return Column(
          children: [
            Obx(() {
              // The sample data has no Rx behind the title; the loaded flag
              // keeps this Obx observing something.
              final isReady = c.isLoaded.value;
              final conv = c.avatarConversation;
              return ConversationHeader(
                title: c.title,
                status: isReady ? c.status : null,
                avatar: conversationAvatarFor(conv, presence: c.presenceDot),
                isEncrypted: c.isLocked.value || c.isBlocked.value,
                onInfoTap: () => Get.toNamed(
                  AppRoutes.chatInfoOf(c.conversationId),
                  arguments: c.isLocked.value || c.isBlocked.value,
                ),
                onBack: Get.back,
                trailing: [
                  if (c.canUseAi)
                    AiHeaderButton(onPressed: () => openAi(context, c.ai)),
                ],
              );
            }),
            const AppOfflineBar(),
            Obx(
              () => c.isDeviceLimit.value
                  ? DeviceLimitBanner(onTap: c.openDeviceLimit)
                  : const SizedBox.shrink(),
            ),
            Expanded(child: _MessageArea(controller: c)),
            Obx(() {
              final label = c.typingLabel;
              return AnimatedSize(
                duration: AppDurations.fast,
                curve: AppCurves.out,
                alignment: Alignment.topLeft,
                child: label == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.xs,
                          AppSpacing.lg,
                          AppSpacing.xs,
                        ),
                        child: TypingDots(label: label),
                      ),
              );
            }),
            ConversationComposer(controller: c),
          ],
        );
      }),
    );
  }
}

class _MessageArea extends StatelessWidget {
  const _MessageArea({required this.controller});

  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(
      children: [
        Positioned.fill(
          child: Obx(() {
            if (!c.isLoaded.value) return const _SkeletonBubbles();
            final items = c.items;
            final uploads = c.uploads;
            if (items.isEmpty && uploads.isEmpty) {
              return const _EmptyConversation();
            }
            return ListView.builder(
              key: c.listKey,
              reverse: true,
              controller: c.scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              itemCount: uploads.length + items.length,
              itemBuilder: (context, index) {
                if (index >= uploads.length) {
                  return _row(context, c, items[index - uploads.length]);
                }
                final upload = uploads[uploads.length - 1 - index];
                return UploadBubble(
                  key: ValueKey(upload.id),
                  upload: upload,
                  onRetry: () => c.retryUpload(upload),
                  onCancel: () => c.cancelUpload(upload),
                );
              },
            );
          }),
        ),
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.xs,
          child: Obx(
            () => ScrollToLatestButton(
              isVisible: c.isAway.value,
              count: c.newAway.value,
              onPressed: c.scrollToLatest,
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ConversationController c, ChatItem item) {
    final child = switch (item.kind) {
      ChatItemKind.message => _message(context, c, item),
      ChatItemKind.day => DayDivider(label: item.label),
      ChatItemKind.unread => UnreadDivider(label: item.label),
      ChatItemKind.system => SystemRow(text: item.label),
      ChatItemKind.loadingOlder => const LoadingOlderRow(),
      ChatItemKind.olderError => OlderErrorRow(onRetry: c.retryOlder),
      ChatItemKind.start => const StartRow(),
    };
    return KeyedSubtree(
      key: item.kind == ChatItemKind.unread ? c.unreadKey : c.keyFor(item),
      child: child,
    );
  }
}

Widget _message(BuildContext context, ConversationController c, ChatItem item) {
  final m = item.message!;
  if (m.kind != 'form') return _bubble(context, c, item);
  // Reads the stored submission and the highlight, so the card follows both.
  return Obx(() {
    final card = c.formCardOf(m);
    if (card == null) return _bubble(context, c, item);
    final isSent = c.isSentForm(card);
    final state = c.formStateOf(m);
    final reactions = c.reactionsOf(m);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.bubbleGap),
      child: Column(
        crossAxisAlignment: m.isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          AppFormCard(
            data: card,
            isSent: isSent,
            senderName: !isSent && item.showName ? m.sender : null,
            isFresh: item.isFresh,
            state: state,
            problem: state == AppFormCardState.failed
                ? c.formProblemOf(m)
                : null,
            isHighlighted: c.highlighted.contains(m.msgId),
            stripLabel: card.isTicket && !card.isPending
                ? '${TicketsTexts.ticketMarker} #${card.id}'
                : null,
            actions: card.isTicket && !card.isPending
                ? TicketCardActions(card: card, controller: c)
                : null,
            statusMark: m.isMine
                ? MessageStatusMark(status: m.status, isDirect: c.isDirect)
                : null,
            onTap: () => c.tapForm(m, card),
            onEdit: c.canEditForm(m, card) ? () => c.editForm(m, card) : null,
            onLongPress: () => MessageActionsSheet.show(context, c, m),
          ),
          ReactionChips(
            reactions: reactions,
            onToggle: (emoji) => c.toggleReaction(m, emoji),
          ),
        ],
      ),
    );
  });
}

Widget _bubble(BuildContext context, ConversationController c, ChatItem item) {
  final m = item.message!;
  // Reads the highlight, so the bubble flashes when opened from a quote.
  return Obx(
    () => _bubbleOf(context, c, item, c.highlighted.contains(m.msgId)),
  );
}

Widget _bubbleOf(
  BuildContext context,
  ConversationController c,
  ChatItem item,
  bool isHighlighted,
) {
  final m = item.message!;
  return MessageBubble(
    isHighlighted: isHighlighted,
    onOpenOriginal: m.replyTo == null ? null : () => c.openOriginal(m.replyTo!),
    item: item,
    isDirect: c.isDirect,
    original: c.originalOf(m),
    onLongPress: () => MessageActionsSheet.show(context, c, m),
    onRetry: () => c.retry(m),
    reactions: c.reactionsOf(m),
    onReact: (emoji) => c.toggleReaction(m, emoji),
    attachmentOf: (tag) => AttachmentView(tag: tag, controller: c),
    people: c.mentionPeople,
    onReviewKey: () {
      c.keyChangeMember = m.sender.toLowerCase();
      KeyChangeSheet.open(context, c);
    },
  );
}

class _SkeletonBubbles extends StatelessWidget {
  const _SkeletonBubbles();

  @override
  Widget build(BuildContext context) {
    const rows = [(false, 180.0), (true, 140.0), (false, 220.0), (true, 100.0)];
    return AppSkeletonScope(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final (isMine, width) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Align(
                  alignment: isMine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: AppSkeleton(
                    width: width,
                    height: 44,
                    radius: AppRadius.bubble,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppStateImage(
          kind: AppStateImageKind.emptyChats,
          size: AppSpacing.stateImageSmall,
        ),
        SizedBox(height: AppSpacing.sm),
        Text('Say hello', style: AppText.readable),
      ],
    ),
  );
}
