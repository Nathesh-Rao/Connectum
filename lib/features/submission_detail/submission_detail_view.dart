import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import 'submission_detail_controller.dart';

class SubmissionDetailView extends GetView<SubmissionDetailController> {
  const SubmissionDetailView({super.key, required this.submissionId});

  final String submissionId;

  @override
  String? get tag => submissionId;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [AppStateImageKind.error]);
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                AppButton.icon(
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: Get.back,
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(
                  child: Text('Submission detail', style: AppText.title),
                ),
              ],
            ),
          ),
          const AppOfflineBar(),
          Expanded(
            child: Obx(
              () => AppStateView(
                state: c.viewState.value,
                errorMessage: 'This submission is not saved on this phone.',
                onRetry: c.load,
                child: _Content(controller: c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.controller});

  final SubmissionDetailController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final d = c.card.value;
      if (d == null) return const SizedBox.shrink();
      final isMine = d.by.toLowerCase() == c.me.toLowerCase();
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.sm,
          AppSpacing.page,
          AppSpacing.xl,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.status != null) ...[
                _StatusLabel(text: d.status!),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(d.caption, style: AppText.title),
              const SizedBox(height: AppSpacing.xxs),
              Text(d.label, style: AppText.readable),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${isMine ? 'Submitted by' : 'Shared by'} ${d.by} · '
                '${ChatTime.date(d.ts)}, ${ChatTime.time(d.ts)}',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              if (d.entries.isEmpty && d.grids.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'No values were saved with this submission.',
                    style: AppText.readable,
                  ),
                ),
              for (var i = 0; i < d.entries.length; i++)
                AppKeyValueRow(
                  entry: d.entries[i],
                  showCoordinates: true,
                  hasDivider: true,
                ),
              for (final g in d.grids) _GridTable(grid: g),
              const SizedBox(height: AppSpacing.md),
              _Footer(
                card: d,
                isEditable: c.canEdit,
                onEdit: c.edit,
                canDelete: c.canDelete,
                isDeleting: c.isDeleting.value,
                onDelete: () =>
                    c.delete(() => confirmDeleteSubmission(context, d)),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: const BoxDecoration(
      color: AppColors.primaryTint,
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.badge)),
    ),
    child: Text(
      text,
      style: AppText.label.copyWith(color: AppColors.primaryStrong),
    ),
  );
}

/// A grid section as a small table: its columns' captions, then one line per
/// row. It scrolls sideways when the columns do not fit.
class _GridTable extends StatelessWidget {
  const _GridTable({required this.grid});

  final FormGrid grid;

  @override
  Widget build(BuildContext context) {
    const cell = EdgeInsets.symmetric(vertical: 6, horizontal: 8);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(grid.caption, style: AppText.fieldLabel),
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.xs),
              ),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth:
                      MediaQuery.sizeOf(context).width -
                      AppSpacing.page * 2 -
                      AppSpacing.lg * 2 -
                      2,
                ),
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: AppColors.line),
                  ),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: AppColors.fill),
                      children: [
                        for (final c in grid.columns)
                          Padding(
                            padding: cell,
                            child: Text(c, style: AppText.label),
                          ),
                      ],
                    ),
                    for (final row in grid.rows)
                      TableRow(
                        children: [
                          for (final v in row)
                            Padding(
                              padding: cell,
                              child: Text(
                                v.isEmpty ? '-' : v,
                                style: AppText.readableStrong,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.card,
    required this.isEditable,
    required this.onEdit,
    required this.canDelete,
    required this.isDeleting,
    required this.onDelete,
  });

  final FormCardData card;
  final bool isEditable;
  final VoidCallback onEdit;
  final bool canDelete;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEditable)
          AppButton.text(
            label: card.canResubmit ? 'Fix and send again' : 'Edit submission',
            tone: AppTextButtonTone.accent,
            onPressed: onEdit,
          )
        else if (!canDelete)
          Text(
            card.isPending ? 'Waiting to send' : 'Read-only · ${card.by}',
            style: AppText.caption,
          ),
        if (canDelete)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: AppButton.secondary(
              label: 'Delete submission',
              isDanger: true,
              onPressed: isDeleting ? null : onDelete,
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmDeleteSubmission(
  BuildContext context,
  FormCardData d,
) async {
  final isSure = await AppBottomSheet.show<bool>(
    context,
    title: 'Delete this submission?',
    child: Builder(
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${d.caption} #${d.id} will be removed. Its history stays.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: 'Delete',
            isDanger: true,
            onPressed: () => Navigator.of(sheet).pop(true),
          ),
          AppButton.text(
            label: 'Cancel',
            onPressed: () => Navigator.of(sheet).pop(false),
          ),
        ],
      ),
    ),
  );
  return isSure ?? false;
}
