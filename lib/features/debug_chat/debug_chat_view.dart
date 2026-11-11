import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_scaffold.dart';
import '../conversation/conversation_controller.dart';
import '../conversation/models/chat_item.dart';
import '../conversation/widgets/document_card.dart';
import '../conversation/widgets/chat_rows.dart';
import '../conversation/widgets/message_bubble.dart';
import 'debug_chat_controller.dart';
import 'debug_chat_samples.dart';

class DebugChatView extends GetView<DebugChatController> {
  const DebugChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          const DebugChatSamples(),
          const SizedBox(height: AppSpacing.md),
          for (final item in c.items)
            item.kind == ChatItemKind.day
                ? DayDivider(label: item.label)
                : MessageBubble(
                    item: item,
                    isDirect: false,
                    original: null,
                    onLongPress: () {},
                    onRetry: () {},
                    reactions: const [],
                    onReact: (_) {},
                    attachmentOf: (tag) => tag.isImage
                        ? const SizedBox.shrink()
                        : Obx(
                            () => DocumentCard(
                              tag: tag,
                              state: c.stateOf(tag),
                              progress: c.progress[tag.url] ?? 0,
                              error: tag.isEncrypted
                                  ? ConversationController.undecryptable
                                  : null,
                              onDownload: () => c.play(tag),
                              onOpen: () {},
                              onCancel: () => c.cancel(tag),
                              onShare: () {},
                            ),
                          ),
                    people: DebugChatController.people,
                    onReviewKey: () {},
                  ),
        ],
      ),
    );
  }
}
