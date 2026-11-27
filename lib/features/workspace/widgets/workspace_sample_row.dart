import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/tour/tour_texts.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../core/widgets/message_selection/selectable_row.dart';
import '../workspace_tour.dart';
import 'workspace_message.dart';

/// The sample note of the Work Space tour: the real note bubble with a
/// "Sample" tag. It takes no touch; its selection and swipe are the tour's.
class WorkspaceSampleRow extends StatelessWidget {
  const WorkspaceSampleRow({super.key, required this.tour});

  final WorkspaceTour tour;

  @override
  Widget build(BuildContext context) {
    final demo = tour.demo;
    final note = demo.note;
    if (note == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: SelectableRow(
        selection: demo.selection,
        id: note.msgId,
        swipeKey: tour.swipeKey,
        onSwipeReply: () {},
        child: KeyedSubtree(
          key: tour.noteKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              WorkspaceMessage(message: note, original: null, me: 'me'),
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.xxs),
                child: AppTag(
                  label: TourTexts.sampleTag,
                  tone: AppTagTone.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
