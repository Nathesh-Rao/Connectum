import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../chats_controller.dart';
import '../models/message_hit.dart';
import 'conversation_tile.dart';

class SearchResults extends StatelessWidget {
  const SearchResults({super.key, required this.controller});

  final ChatsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (!c.hasSearched.value) return const SizedBox.shrink();
      final conversations = c.searchConversations.toList();
      final messages = c.searchMessages.toList();
      if (conversations.isEmpty && messages.isEmpty) {
        return const Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxl),
            child: Text('No conversations found.', style: AppText.body),
          ),
        );
      }
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        children: [
          if (conversations.isNotEmpty) ...[
            const _Heading('Conversations'),
            for (final conv in conversations)
              ConversationTile(
                key: ValueKey('c-${conv.convId}'),
                conversation: conv,
                controller: c,
                onTap: () => c.open(conv.convId),
              ),
          ],
          if (messages.isNotEmpty) ...[
            const _Heading('Messages'),
            for (var i = 0; i < messages.length; i++)
              _MessageRow(
                hit: messages[i],
                now: c.minute,
                onTap: () => c.open(messages[i].convId),
              ),
          ],
        ],
      );
    });
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
    child: Text(text, style: AppText.eyebrow),
  );
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.hit,
    required this.now,
    required this.onTap,
  });

  final MessageHit hit;
  final Rx<DateTime> now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.rowTitle,
                  ),
                ),
                Obx(
                  () => Text(
                    RelativeTime.label(hit.ts, now.value),
                    style: AppText.caption,
                  ),
                ),
              ],
            ),
            Text(
              hit.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.rowCaption,
            ),
          ],
        ),
      ),
    );
  }
}
