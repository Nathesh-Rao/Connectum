import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_inbox.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../inbox_approvals_controller.dart';
import '../models/approval_entries.dart';
import '../models/approval_quick_filter.dart';
import 'inbox_chip_bar.dart';
import 'inbox_filter_sheet.dart';

/// The Approvals tab's row of selected filters (status, scope, entries), each
/// with an ×: the shared [InboxChipBar]. Nothing shows while none is on; the
/// header's filter button opens the popup.
class ApprovalFilterBar extends StatelessWidget {
  const ApprovalFilterBar({super.key, required this.controller});

  final InboxApprovals controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => InboxChipBar(
        keyPrefix: 'approval',
        chips: [
          for (final s in ApprovalQuick.selectedOf(
            c.primary.value,
            c.side.value,
            c.panel.value.entries,
          ))
            InboxChipData(
              id: s.id,
              label: s.label,
              onRemove: () => c.removeSelected(s),
            ),
        ],
      ),
    );
  }
}

/// The popup the Filters button opens.
class ApprovalFilterPopup {
  ApprovalFilterPopup._();

  static Future<void> show(BuildContext context, InboxApprovals c) {
    return InboxFilterSheet.open(
      context,
      ApprovalQuickPanel(controller: c, draft: c.newQuickDraft()),
    );
  }
}

/// The popup's content: Status, Scope (only with direct reports) and Entries,
/// then Clear and Apply. Nothing applies until Apply. Public so a test can
/// draw it without a popup.
class ApprovalQuickPanel extends StatelessWidget {
  const ApprovalQuickPanel({
    super.key,
    required this.controller,
    required this.draft,
  });

  final InboxApprovals controller;
  final ApprovalQuickDraft draft;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.md,
            end: AppSpacing.xs,
            top: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            children: [
              const Expanded(child: Text('Filters', style: AppText.subtitle)),
              Semantics(
                button: true,
                label: 'Close the filters',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox(
                    width: AppInbox.hit,
                    height: AppInbox.hit,
                    child: Icon(
                      Icons.close_rounded,
                      size: AppInbox.discIcon,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: AppColors.line),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Status(controller: controller, draft: draft),
                if (draft.hasTeam) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _Scope(draft: draft),
                ],
                const SizedBox(height: AppSpacing.sm),
                _Entries(controller: controller, draft: draft),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: 'Clear',
                    onPressed: () {
                      controller.clearQuick();
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton.primary(
                    label: 'Apply',
                    isCentered: true,
                    onPressed: () {
                      controller.applyQuick(
                        draft.primary.value,
                        draft.side.value,
                        draft.entries.toList(),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.controller, required this.draft});

  final InboxApprovals controller;
  final ApprovalQuickDraft draft;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final counts = controller.statusCountsFor(draft.side.value);
      final on = draft.primary.value;
      return InboxFilterSection(
        title: 'Status',
        icon: Icons.donut_large_rounded,
        tone: AppInbox.whereTone,
        count: on == ApprovalPrimary.all ? 0 : 1,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final p in ApprovalPrimary.values)
                InboxFilterChip(
                  key: ValueKey('approval-status-${p.name}'),
                  label: '${p.label} ${counts[p] ?? 0}',
                  isSelected: p == on,
                  isDimmed: (counts[p] ?? 0) == 0,
                  onTap: () => draft.pickPrimary(p),
                ),
            ],
          ),
        ],
      );
    });
  }
}

class _Scope extends StatelessWidget {
  const _Scope({required this.draft});

  final ApprovalQuickDraft draft;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final on = draft.side.value;
      return InboxFilterSection(
        title: 'Scope',
        icon: Icons.groups_rounded,
        tone: AppInbox.peopleTone,
        count: on == ApprovalSide.team ? 1 : 0,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              InboxFilterChip(
                key: const ValueKey('approval-scope-me'),
                label: 'Me',
                isSelected: on == ApprovalSide.me,
                onTap: () => draft.pickSide(ApprovalSide.me),
              ),
              InboxFilterChip(
                key: const ValueKey('approval-scope-team'),
                label: 'My Team',
                isSelected: on == ApprovalSide.team,
                onTap: () => draft.pickSide(ApprovalSide.team),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _Entries extends StatelessWidget {
  const _Entries({required this.controller, required this.draft});

  final InboxApprovals controller;
  final ApprovalQuickDraft draft;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final counts = controller.entryCounts;
      final ticked = draft.entries.toList();
      return InboxFilterSection(
        title: 'Entries',
        icon: Icons.manage_search_rounded,
        tone: AppInbox.detailsTone,
        count: ticked.length,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final e in draft.offered)
                InboxFilterChip(
                  key: ValueKey('approval-entry-${e.name}'),
                  label: '${e.label} ${counts[e] ?? 0}',
                  isSelected: ticked.contains(e),
                  isDimmed: (counts[e] ?? 0) == 0,
                  onTap: () => draft.toggleEntry(e),
                ),
            ],
          ),
        ],
      );
    });
  }
}
