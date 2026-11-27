import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../conversation_tour.dart';
import '../models/chat_item.dart';
import 'message_bubble.dart';

/// One sample message of the chat tour: the real bubble with a "Sample" tag.
/// It takes no touch, and its selection and swipe are the tour's own.
class ConversationSampleRow extends StatelessWidget {
  const ConversationSampleRow({
    super.key,
    required this.tour,
    required this.item,
    required this.isDirect,
  });

  final ConversationTour tour;
  final ChatItem item;
  final bool isDirect;

  @override
  Widget build(BuildContext context) {
    final demo = tour.demo;
    final m = item.message!;
    final content = Column(
      crossAxisAlignment: m.isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        MessageBubble(
          item: item,
          isDirect: isDirect,
          original: null,
          onLongPress: () {},
          onRetry: () {},
          reactions: const [],
          onReact: (_) {},
          attachmentOf: (_) => const SizedBox.shrink(),
          people: const MentionPeople(me: 'me'),
          onReviewKey: () {},
        ),
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xxs),
          child: AppTag(label: TourTexts.sampleTag, tone: AppTagTone.accent),
        ),
      ],
    );
    return IgnorePointer(
      child: SelectableRow(
        selection: demo.selection,
        id: m.msgId,
        swipeKey: m.isMine ? null : tour.swipeKey,
        onSwipeReply: demo.caps.canReply ? () {} : null,
        child: m.isMine
            ? KeyedSubtree(key: tour.messageKey, child: content)
            : content,
      ),
    );
  }
}
