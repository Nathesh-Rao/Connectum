import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import '../../data/smart_view/models/sv_row.dart';
import 'struct_records_controller.dart';
import 'widgets/struct_record_card.dart';

/// `#tstruct <name>`: the records of one structure as cards, with New record
/// and, on the person's own records, Edit and Delete (the web's Records page).
class StructRecordsView extends GetView<StructRecordsController> {
  const StructRecordsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
    ]);
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
                Expanded(
                  child: Obx(
                    () => Text(
                      c.title.value,
                      style: AppText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Obx(
                  () => c.viewState.value == AppViewState.content
                      ? Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.xs),
                          child: _CountPill(total: c.total.value),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Obx(
            () => c.canAdd.value
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      0,
                      AppSpacing.page,
                      AppSpacing.xs,
                    ),
                    child: AppButton.primary(
                      label: 'New record',
                      icon: Icons.add,
                      isCompact: true,
                      onPressed: c.addRecord,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Obx(
              () => AppStateView(
                state: c.viewState.value,
                emptyTitle: 'No records yet',
                emptyMessage: c.canAdd.value
                    ? "Records you submit through this structure's form show up here."
                    : null,
                emptyActionLabel: c.canAdd.value ? 'New record' : null,
                onEmptyAction: c.addRecord,
                errorMessage: c.errorText.value,
                onRetry: c.retry,
                loadingChild: const _Skeleton(),
                child: _List(controller: c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final StructRecordsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final source = c.view?.source;
      final rows = c.rows.toList();
      final busy = c.deletingIds.toSet();
      return AppRefresh(
        controller: c.scroll,
        onRefresh: c.refreshList,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xs,
              AppSpacing.page,
              AppSpacing.xl,
            ),
            sliver: SliverList.separated(
              itemCount: rows.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                if (i == rows.length) {
                  return Obx(
                    () => c.isLoadingMore.value
                        ? const Padding(
                            padding: EdgeInsets.all(AppSpacing.md),
                            child: Center(child: AppSpinner()),
                          )
                        : const SizedBox.shrink(),
                  );
                }
                final row = rows[i];
                final canChange = c.canChange(row);
                return StructRecordCard(
                  key: ValueKey('struct-record-${row.id}'),
                  data: StructRecordCardData.of(source!, row),
                  isBusy: busy.contains(row.id),
                  onEdit: canChange ? () => c.editRecord(row) : null,
                  onDelete: c.canDelete(row)
                      ? () async {
                          if (await confirmDeleteRecord(context, row)) {
                            await c.deleteRecord(row);
                          }
                        }
                      : null,
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

/// The web's words (`RecordsBrowser.jsx`).
Future<bool> confirmDeleteRecord(BuildContext context, SvRow row) async {
  final isSure = await AppBottomSheet.show<bool>(
    context,
    title: 'Delete this record?',
    child: Builder(
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Record #${row.id} will be permanently deleted. This can't be undone.",
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

class _CountPill extends StatelessWidget {
  const _CountPill({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.statusPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        total == 1 ? '1 record' : '$total records',
        style: AppText.label.copyWith(color: AppColors.primaryStrong),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonScope(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xs,
          AppSpacing.page,
          0,
        ),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, _) =>
            const AppSkeleton(height: 120, radius: AppRadius.card),
      ),
    );
  }
}
