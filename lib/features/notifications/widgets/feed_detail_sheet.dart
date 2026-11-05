import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/relative_time.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../models/feed_item.dart';
import '../notification_texts.dart';

/// The title and the whole message of an item, for those that lead nowhere
/// else (admin console, about me, Axpert, smart prompt, anything new).
class FeedDetailSheet extends StatelessWidget {
  const FeedDetailSheet({super.key, required this.item, required this.text});

  final FeedItem item;

  /// The message to show; for an end-to-end item the opened text.
  final Future<String?> text;

  static Future<void> show(
    BuildContext context,
    FeedItem item,
    Future<String?> text,
  ) => AppBottomSheet.show<void>(
    context,
    title: item.title.isEmpty ? NotificationTexts.screenTitle : item.title,
    child: FeedDetailSheet(item: item, text: text),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.ts > 0)
          Text(
            RelativeTime.label(item.ts, DateTime.now()),
            style: AppText.caption.copyWith(color: AppColors.muted),
          ),
        const SizedBox(height: AppSpacing.xs),
        FutureBuilder<String?>(
          future: text,
          builder: (context, snapshot) {
            final body = snapshot.connectionState == ConnectionState.done
                ? (snapshot.data ?? NotificationTexts.encrypted)
                : '';
            return Text(body, style: AppText.body);
          },
        ),
      ],
    );
  }
}
