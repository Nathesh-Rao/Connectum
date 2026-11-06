import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_pill_bar.dart';
import '../models/chat_filter.dart';

/// The chips above the Chats list: All, Direct & Teams and, while a thread
/// exists, Threads with the unread of its conversations.
class ChatFilterBar extends StatelessWidget {
  const ChatFilterBar({
    super.key,
    required this.filter,
    required this.hasThreads,
    required this.threadUnread,
    required this.onSelected,
  });

  final Rx<ChatFilterKind> filter;
  final RxBool hasThreads;
  final RxInt threadUnread;
  final ValueChanged<ChatFilterKind> onSelected;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final kinds = [
        ChatFilterKind.all,
        ChatFilterKind.direct,
        if (hasThreads.value) ChatFilterKind.threads,
      ];
      return AppPillBar(
        size: AppPillSize.compact,
        pills: [
          const AppPill(label: 'All'),
          const AppPill(label: 'Direct & Teams'),
          if (hasThreads.value)
            AppPill(label: 'Threads', count: threadUnread.value),
        ],
        selected: kinds.indexOf(filter.value).clamp(0, kinds.length - 1),
        onSelected: (i) => onSelected(kinds[i]),
      );
    });
  }
}
