import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../models/pinned_line.dart';
import '../workspace_controller.dart';

/// The pinned notes under the header, like the web's bar: the newest one in
/// a line (tap to show it in the thread), "n pinned" to open the whole list
/// when there are several, and a close button that unpins. Nothing is drawn
/// when no note is pinned.
class WorkspacePinnedBar extends StatelessWidget {
  const WorkspacePinnedBar({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final lines = c.pinLines();
      if (lines.isEmpty) return const SizedBox(width: double.infinity);
      final isOpen = c.isPinListOpen.value && lines.length > 1;
      return Container(
        key: const ValueKey('pinned-bar'),
        decoration: const BoxDecoration(
          color: AppColors.surfaceSubtle,
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: AnimatedSize(
          duration: AppDurations.fast,
          curve: AppCurves.out,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.minTapTarget,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _Line(
                        line: lines.first,
                        onTap: () => c.openNote(lines.first.id),
                        isLead: true,
                      ),
                    ),
                    if (lines.length > 1)
                      InkWell(
                        key: const ValueKey('pinned-count'),
                        onTap: c.togglePinList,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: AppSpacing.minTapTarget,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${lines.length} pinned',
                                style: AppText.label.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                              Icon(
                                isOpen ? Icons.expand_less : Icons.expand_more,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    AppButton.icon(
                      key: const ValueKey('pinned-unpin'),
                      icon: Icons.close,
                      semanticLabel: 'Unpin',
                      onPressed: () => c.unpinNote(lines.first.id),
                    ),
                  ],
                ),
              ),
              if (isOpen)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final line in lines)
                        Row(
                          children: [
                            Expanded(
                              child: _Line(
                                line: line,
                                onTap: () => c.openNote(line.id),
                              ),
                            ),
                            AppButton.icon(
                              icon: Icons.close,
                              semanticLabel: 'Unpin',
                              onPressed: () => c.unpinNote(line.id),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line, required this.onTap, this.isLead = false});

  final PinnedLine line;
  final VoidCallback onTap;
  final bool isLead;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.push_pin_outlined,
              size: 16,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pinned',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: AppColors.muted),
                  ),
                  Text(
                    line.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.chatPreview,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
