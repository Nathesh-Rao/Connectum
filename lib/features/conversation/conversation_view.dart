import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/features/ai_chat/ai_chat.dart';
import 'package:connectum/features/tickets/tickets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import 'conversation_tour.dart';
import 'conversation_controller.dart';
import 'models/chat_item.dart';
import 'widgets/attachment_view.dart';
import 'widgets/chat_rows.dart';
import 'widgets/conversation_composer.dart';
import 'widgets/conversation_sample_row.dart';
import 'widgets/conversation_header.dart';
import 'widgets/conversation_selection.dart';
import 'widgets/device_limit_banner.dart';
import 'widgets/key_change_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_status_mark.dart';
import 'widgets/reaction_chips.dart';
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
        return PopScope(
          canPop: !c.selection.isActive && !c.isTourActive,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (c.isTourActive) {
              c.cancelTour();
            } else {
              c.selection.clear();
            }
          },
          child: Column(
            children: [
              SelectionHeaderSwitcher(
                isSelecting:
                    c.selection.isActive ||
                    (c.tour?.demo.selection.isActive ?? false),
                selectionBar: KeyedSubtree(
                  key: c.tour?.selectionBarKey,
                  child: _selectionBar(c),
                ),
                header: KeyedSubtree(
                  key: c.tour?.headerKey,
                  child: Obx(() {
                    // The sample data has no Rx behind the title; the loaded flag
                    // keeps this Obx observing something.
                    final isReady = c.isLoaded.value;
                    final conv = c.avatarConversation;
                    return ConversationHeader(
                      title: c.title,
                      status: isReady ? c.status : null,
                      avatar: conversationAvatarFor(
                        conv,
                        presence: c.presenceDot,
                        mood: c.mood,
                      ),
                      isEncrypted: c.isLocked.value || c.isBlocked.value,
                      onInfoTap: () => Get.toNamed(
                        AppRoutes.chatInfoOf(c.conversationId),
                        arguments: c.isLocked.value || c.isBlocked.value,
                      ),
                      onAvatarTap: c.personUsername == null
                          ? null
                          : c.openPersonProfile,
                      onBack: Get.back,
                      trailing: [
                        if (c.canUseAi)
                          AiHeaderButton(
                            onPressed: () => openAi(context, c.ai),
                          ),
                      ],
                    );
                  }),
                ),
              ),
              const AppOfflineBar(),
              Obx(
                () => c.isDeviceLimit.value
                    ? DeviceLimitBanner(onTap: c.openDeviceLimit)
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: c.tour?.areaKey,
                  child: _MessageArea(controller: c),
                ),
              ),
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
              KeyedSubtree(
                key: c.tour?.composerKey,
                child: ConversationComposer(controller: c),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// The selection bar: the chat's own, or the sample's while the tour shows
/// sample messages.
Widget _selectionBar(ConversationController c) => Obx(() {
  final demo = c.tour?.demo;
  final isSample = demo != null && demo.isOn.value;
  final bar = ConversationSelectionBar(
    controller: c,
    sample: isSample ? demo : null,
  );
  return isSample ? IgnorePointer(child: bar) : bar;
});

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
            final tour = c.tour;
            final demo = tour?.demo;
            final samples = demo != null && demo.isOn.value
                ? demo.items
                : const <ChatItem>[];
            // The tour presses and holds one of my messages, and slides one
            // that can be replied to.
            final holdId = tour == null
                ? null
                : ConversationTour.holdMessage(items, c.targetOf)?.msgId;
            final swipeId = tour == null
                ? null
                : ConversationTour.swipeMessage(items, c.targetOf)?.msgId;
            if (items.isEmpty && uploads.isEmpty && samples.isEmpty) {
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
              itemCount: samples.length + uploads.length + items.length,
              itemBuilder: (context, index) {
                if (index < samples.length) {
                  return ConversationSampleRow(
                    key: ValueKey(samples[index].message?.msgId),
                    tour: tour!,
                    item: samples[index],
                    isDirect: c.isDirect,
                  );
                }
                index -= samples.length;
                if (index >= uploads.length) {
                  final item = items[index - uploads.length];
                  final id = item.message?.msgId;
                  return _row(
                    context,
                    c,
                    item,
                    tourKey: id != null && id == holdId
                        ? tour?.messageKey
                        : null,
                    swipeKey: id != null && id == swipeId
                        ? tour?.swipeKey
                        : null,
                  );
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
        Positioned.fill(
          child: Obx(() {
            final demo = c.tour?.demo;
            final isSample = demo != null && demo.isOn.value;
            return ConversationReactionOverlay(
              controller: c,
              barKey: c.tour?.reactionKey,
              sample: isSample ? demo : null,
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

  Widget _row(
    BuildContext context,
    ConversationController c,
    ChatItem item, {
    GlobalKey? tourKey,
    GlobalKey<SwipeToReplyState>? swipeKey,
  }) {
    final child = switch (item.kind) {
      ChatItemKind.message => SelectableRow(
        selection: c.selection,
        id: item.message?.msgId ?? '',
        onSwipeReply: _swipeReplyOf(c, item.message),
        swipeKey: swipeKey,
        child: tourKey == null
            ? _message(context, c, item)
            : KeyedSubtree(key: tourKey, child: _message(context, c, item)),
      ),
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

/// The swipe starts the same reply as the selection bar, under the same rule.
VoidCallback? _swipeReplyOf(ConversationController c, Message? m) {
  if (m == null || !c.targetOf(m).canReply) return null;
  return () => c.startReply(m);
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
            stripLabel: c.recordMarkerOf(card),
            actions: c.recordIdOf(card) != null
                ? RecordCardActions(
                    recordId: c.recordIdOf(card)!,
                    tickets: c.tickets,
                    summary: card.record,
                    onAction: (context, id) {
                      final detail = c.ticketDetailOf(card);
                      if (detail != null) {
                        TicketActionSheet.show(context, detail, id);
                      }
                    },
                  )
                : null,
            statusMark: m.isMine
                ? MessageStatusMark(status: m.status, isDirect: c.isDirect)
                : null,
            onTap: () => c.tapForm(m, card),
            onEdit: c.canEditForm(m, card) ? () => c.editForm(m, card) : null,
            onLongPress: () => c.onMessageLongPress(m),
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
    onLongPress: () => c.onMessageLongPress(m),
    onRetry: () => c.retry(m),
    reactions: c.reactionsOf(m),
    onReact: (emoji) => c.toggleReaction(m, emoji),
    attachmentOf: (tag) =>
        AttachmentView(tag: tag, controller: c, isMine: m.isMine),
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
