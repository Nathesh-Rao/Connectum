import 'package:flutter/material.dart';

import '../../selection/selection_rules.dart';
import 'package:connectum/core/theme/theme.dart';
import '../app_button.dart';

/// One action of the selection bar.
class SelectionBarItem {
  const SelectionBarItem({
    required this.action,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final SelectionAction action;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
}

/// Replaces the thread's header while messages are selected: back, the count,
/// the icons that fit and a "More" menu for the rest.
class SelectionAppBar extends StatelessWidget {
  const SelectionAppBar({
    super.key,
    required this.count,
    required this.items,
    required this.onExit,
    this.isEditIcon = false,
  });

  final int count;
  final List<SelectionBarItem> items;
  final VoidCallback onExit;

  /// Edit is one of the icons (chats) instead of sitting in the menu (notes).
  final bool isEditIcon;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final split = SelectionRules.split(
      [for (final i in items) i.action],
      width,
      isEditIcon: isEditIcon,
    );
    SelectionBarItem item(SelectionAction a) =>
        items.firstWhere((i) => i.action == a);
    final icons = [for (final a in split.icons) item(a)];
    final overflow = [for (final a in split.overflow) item(a)];
    return Container(
      height: AppSpacing.conversationHeaderHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Exit selection',
            child: AppButton.icon(
              icon: Icons.arrow_back,
              semanticLabel: 'Exit selection',
              onPressed: onExit,
            ),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: '$count selected',
              excludeSemantics: true,
              child: Text(
                '$count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.chatHeaderName,
              ),
            ),
          ),
          for (final i in icons)
            Tooltip(
              message: i.label,
              child: AppButton.icon(
                icon: i.icon,
                semanticLabel: i.label,
                onPressed: i.onTap,
              ),
            ),
          if (overflow.isNotEmpty) _More(items: overflow),
        ],
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.items});

  final List<SelectionBarItem> items;

  @override
  Widget build(BuildContext context) => PopupMenuButton<SelectionAction>(
    tooltip: 'More',
    icon: const Icon(Icons.more_vert, color: AppColors.muted),
    constraints: const BoxConstraints(minWidth: 160),
    color: AppColors.white,
    onSelected: (a) => items.firstWhere((i) => i.action == a).onTap(),
    itemBuilder: (_) => [
      for (final i in items)
        PopupMenuItem<SelectionAction>(
          value: i.action,
          child: Row(
            children: [
              Icon(
                i.icon,
                size: 20,
                color: i.isDanger ? AppColors.error : AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  i.label,
                  style: i.isDanger
                      ? AppText.rowTitle.copyWith(color: AppColors.error)
                      : AppText.rowTitle,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Fades between the normal header and the selection bar (about 150 ms).
class SelectionHeaderSwitcher extends StatelessWidget {
  const SelectionHeaderSwitcher({
    super.key,
    required this.isSelecting,
    required this.header,
    required this.selectionBar,
  });

  final bool isSelecting;
  final Widget header;
  final Widget selectionBar;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppDurations.reduced,
    child: KeyedSubtree(
      key: ValueKey(isSelecting),
      child: isSelecting ? selectionBar : header,
    ),
  );
}
