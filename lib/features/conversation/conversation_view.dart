import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_skeleton.dart';
import '../../core/widgets/app_state_image.dart';
import 'conversation_controller.dart';
import 'models/chat_item.dart';
import 'widgets/chat_rows.dart';
import 'widgets/conversation_composer.dart';
import 'widgets/conversation_header.dart';
import 'widgets/message_actions_sheet.dart';
import 'widgets/message_bubble.dart';
import 'widgets/scroll_to_latest_button.dart';
import 'widgets/typing_dots.dart';

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
              return ConversationHeader(
                title: c.title,
                status: isReady ? c.status : null,
                isSquareAvatar: c.kind != 'dm',
                presence: c.presenceDot,
                onBack: Get.back,
              );
            }),
            const AppOfflineBar(),
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
            if (items.isEmpty) return const _EmptyConversation();
            return ListView.builder(
              key: c.listKey,
              reverse: true,
              controller: c.scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _row(context, c, items[index]),
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
      ChatItemKind.message => MessageBubble(
        item: item,
        isDirect: c.isDirect,
        original: c.originalOf(item.message!),
        onLongPress: () => MessageActionsSheet.show(context, c, item.message!),
        onRetry: () => c.retry(item.message!),
      ),
      ChatItemKind.day => DayDivider(label: item.label),
      ChatItemKind.unread => UnreadDivider(label: item.label),
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
