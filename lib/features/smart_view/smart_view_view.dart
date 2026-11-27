import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_sv.dart';
import '../../core/theme/app_tones.dart';
import '../../core/theme/app_text.dart';
import '../../core/tour/tour_texts.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_drawer_shell.dart';
import '../../core/widgets/app_speed_dial.dart';
import '../../core/widgets/app_offline_bar.dart';
import '../../core/widgets/app_refresh.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_tag.dart';
import '../../core/widgets/app_spinner.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/smart_view/sv_columns.dart';
import '../../data/smart_view/sv_prefs.dart';
import '../../data/smart_view/sv_query.dart';
import 'smart_view_controller.dart';
import 'widgets/smart_view_drawer.dart';
import 'widgets/smart_view_card.dart';
import 'widgets/smart_view_count_chip.dart';
import 'widgets/smart_view_table.dart';
import 'widgets/sv_chips_strip.dart';
import 'widgets/sv_charts_sheet.dart';
import 'widgets/sv_confirm_sheet.dart';
import 'widgets/sv_controls.dart';
import 'widgets/sv_group_header.dart';
import 'widgets/sv_view_tabs.dart';
import 'widgets/sv_file_chips.dart';
import 'widgets/sv_filter_draft.dart';
import 'widgets/sv_filter_sheet.dart';
import 'widgets/sv_file_preview_dialog.dart';
import 'widgets/sv_kpi_sheet.dart';
import 'widgets/sv_no_match.dart';
import 'widgets/sv_record_sheet.dart';

/// The Smart view tab: the open structure's records as cards or as a table,
/// newest first, with the list of structures in a drawer. No filters, groups
/// or charts yet.
class SmartViewView extends GetView<SmartViewController> {
  const SmartViewView({super.key});

  static const noAccessTitle = 'Not available';
  static const noAccessMessage =
      "This structure is gone, or you can't open it.";
  static const emptyTitle = 'There is nothing here yet';
  static const chooseTitle = 'Choose a smart view';
  static const loadFailed = 'It could not be loaded.';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
      AppStateImageKind.locked,
    ]);
    return Obx(
      () => PopScope(
        canPop: c.canLeave,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) c.onBack();
        },
        child: AppScaffold(
          hasOuterBottomBar: true,
          isScrollable: false,
          padding: EdgeInsets.zero,
          body: AppDrawerShell(
            isOpen: c.isDrawerOpen.value,
            onChanged: c.setDrawer,
            drawer: SmartViewDrawer(controller: c),
            child: Stack(
              children: [
                Column(
                  children: [
                    _Header(controller: c),
                    const AppOfflineBar(),
                    Expanded(child: _Body(controller: c)),
                  ],
                ),
                Positioned.fill(
                  child: Obx(() {
                    final s = c.source;
                    if (s == null || c.viewState != AppViewState.content) {
                      return const SizedBox.shrink();
                    }
                    return AppSpeedDial(
                      buttonKey: c.tour?.fabKey,
                      semanticLabel: 'Actions',
                      closeKey: Object.hash(
                        c.isActive.value,
                        s.name,
                        c.isDrawerOpen.value,
                      ),
                      options: [
                        if (s.canAdd)
                          AppSpeedDialOption(
                            label: 'Add record',
                            icon: Icons.add,
                            tone: AppTones.primary,
                            onSelected: c.add,
                          ),
                        AppSpeedDialOption(
                          label: 'KPI',
                          icon: Icons.insights_outlined,
                          tone: AppTones.green,
                          onSelected: () => SvKpiSheet.show(context, c),
                        ),
                        AppSpeedDialOption(
                          label: 'Charts',
                          icon: Icons.bar_chart_rounded,
                          tone: AppTones.violet,
                          onSelected: () => SvChartsSheet.show(context, c),
                        ),
                      ],
                    );
                  }),
                ),
                _TourFilter(controller: c),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The filter sheet the tour shows for a moment, drawn over the screen (a
/// route would end the tour). It is the real sheet body on the rows now on
/// screen; Apply does nothing and nothing is kept.
class _TourFilter extends StatelessWidget {
  const _TourFilter({required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final demo = controller.tour?.demo;
    if (demo == null) return const SizedBox.shrink();
    return Obx(() {
      final input = controller.engineInput;
      if (!demo.isFilterOpen.value || input == null) {
        return const SizedBox.shrink();
      }
      return Positioned.fill(
        child: IgnorePointer(
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: AppColors.sheetBackdrop),
              ),
              Positioned.fill(
                child: SvFilterSheetBody(
                  draft: SvFilterDraft(input, SmartViewQuery.none),
                  onApply: () {},
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxs,
      ),
      child: Row(
        children: [
          KeyedSubtree(
            key: c.tour?.menuKey,
            child: AppButton.icon(
              icon: Icons.menu,
              semanticLabel: 'Smart views',
              onPressed: c.openDrawer,
            ),
          ),
          Expanded(
            child: Obx(
              () => Text(
                c.title,
                style: AppText.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Obx(
            () => c.isTourSampleShown
                ? const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.xs),
                    child: AppTag(
                      label: TourTexts.sampleTag,
                      tone: AppTagTone.accent,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Obx(() {
            final t = c.table.value;
            if (t == null || t.rows.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: SmartViewCountChip(
                total: t.rows.length,
                shown: c.query.value.isFiltering ? c.shownRows.length : null,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final state = c.viewState;
      final t = c.table.value;
      final canAdd = c.source?.canAdd ?? false;
      final message = t?.errorMessage.value ?? '';
      return AppStateView(
        state: state,
        emptyTitle: state == AppViewState.locked
            ? SmartViewView.noAccessTitle
            : c.isChoosing
            ? SmartViewView.chooseTitle
            : t == null
            ? SmartViewDrawer.emptyTitle
            : SmartViewView.emptyTitle,
        emptyMessage: state == AppViewState.locked
            ? SmartViewView.noAccessMessage
            : null,
        emptyActionLabel: c.isChoosing
            ? 'Show smart views'
            : state == AppViewState.empty && canAdd
            ? 'Add a record'
            : null,
        onEmptyAction: c.isChoosing ? c.openDrawer : c.add,
        errorMessage: message.isEmpty ? SmartViewView.loadFailed : message,
        onRetry: c.reload,
        child: SmartViewContent(controller: c),
      );
    });
  }
}

/// The mode switch above the records, and the records as cards or as a
/// table; changing mode fades and slides one into the other. Nothing is read
/// again: both draw the rows already in memory.
class SmartViewContent extends StatelessWidget {
  const SmartViewContent({super.key, required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    c.askOverwrite = () => SvConfirmSheet.ask(
      context,
      title: 'View changed',
      message: 'This view was changed on another device. Overwrite it?',
      confirm: 'Overwrite',
      cancel: 'Reload',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SvControls(controller: c),
        SvViewTabs(controller: c),
        SvChipsStrip(controller: c),
        Expanded(
          child: Obx(() {
            final mode = c.mode.value;
            final isNoMatch =
                c.query.value.isFiltering &&
                (c.table.value?.rows.isNotEmpty ?? false) &&
                c.shownRows.isEmpty;
            if (isNoMatch) return SvNoMatch(controller: c);
            final page = c.pageSeq.value;
            return AnimatedSwitcher(
              duration: _modeDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, _slide),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey((mode, c.selectedViewId.value)),
                child: mode == SvViewMode.cards
                    ? _Cards(controller: c, page: page)
                    : _Table(controller: c),
              ),
            );
          }),
        ),
      ],
    );
  }

  static const _modeDuration = Duration(milliseconds: 240);

  /// A twelfth of the height of a card: well under 12 dp on a phone list.
  static const _slide = 0.02;
}

class _Cards extends StatelessWidget {
  const _Cards({required this.controller, required this.page});

  final SmartViewController controller;

  /// The page switch this page was built for. While the mode switcher fades
  /// the old page out, only the newest page holds the tour key.
  final int page;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final t = c.table.value;
      if (t == null) return const SizedBox.shrink();
      final grouped = c.grouped;
      final rows = grouped?.rows ?? c.shownRows;
      final versions = Map<int, int>.of(t.versions);
      final columns = c.shownColumns ?? SmartViewColumns.of(t.source);
      final isCurrent = page == c.pageSeq.value;
      final firstCard = grouped == null
          ? 0
          : grouped.flat.indexWhere((l) => !l.isGroup);
      return KeyedSubtree(
        key: PageStorageKey('sv-cards-${t.source.name}'),
        child: AppRefresh(
          onRefresh: c.reload,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs +
                    AppSv.dialClearance +
                    MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList.builder(
                itemCount: (grouped?.flat.length ?? rows.length) + 1,
                itemBuilder: (context, n) {
                  if (n == (grouped?.flat.length ?? rows.length)) {
                    return _Footer(table: t, controller: c);
                  }
                  final line = grouped?.flat[n];
                  if (line != null && line.isGroup) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSv.cardGap),
                      child: SvGroupHeader(
                        line: line,
                        sumLabel: grouped!.sumLabel,
                        onTap: () => c.toggleGroup(line.path!),
                      ),
                    );
                  }
                  final i = line?.row ?? n;
                  final row = rows[i];
                  return Padding(
                    key: ValueKey('sv-${row.id}'),
                    padding: const EdgeInsets.only(bottom: AppSv.cardGap),
                    child: KeyedSubtree(
                      key: isCurrent && n == firstCard ? c.tour?.cardKey : null,
                      child: Obx(
                        () => SmartViewCard(
                          data: columns.cardOf(row),
                          position: i + 1,
                          isExpanded: c.expanded.contains(row.id),
                          onToggle: () => c.toggleExpanded(row.id),
                          isFilesExpanded: c.filesExpanded.contains(row.id),
                          onToggleFiles: () => c.toggleFilesExpanded(row.id),
                          onTap: () => SvRecordSheet.show(
                            context,
                            columns.cardOf(row),
                            onOpenFiles: _opener(context, c),
                          ),
                          onOpenFiles: _opener(context, c),
                          version: versions[row.id] ?? 0,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.controller});

  final SmartViewController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final t = c.table.value;
      if (t == null) return const SizedBox.shrink();
      return KeyedSubtree(
        key: PageStorageKey('sv-table-${t.source.name}'),
        child: SmartViewTable(
          source: t.source,
          rows: c.shownRows,
          columns: c.shownColumns,
          grouped: c.grouped,
          onToggleGroup: c.toggleGroup,
          versions: Map<int, int>.of(t.versions),
          sortKey: c.query.value.sortKey,
          isAscending: c.query.value.isAscending,
          onSort: c.cycleSort,
          onRefresh: c.reload,
          onRowTap: (row) => SvRecordSheet.show(
            context,
            SmartViewColumns.of(t.source).cardOf(row),
            onOpenFiles: _opener(context, c),
          ),
          onOpenFiles: _opener(context, c),
          cache: c.tableCache,
          footer: _Footer(table: t, controller: c),
        ),
      );
    });
  }
}

/// A fixed-height line under the cards, so the list never jumps: the pages
/// still coming, a page that failed (Retry), or the cap.
class _Footer extends StatelessWidget {
  const _Footer({required this.table, required this.controller});

  final SvTable table;
  final SmartViewController controller;

  static const _height = 56.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvLoadNote(controller: controller),
        _line(),
      ],
    );
  }

  Widget _line() {
    return SizedBox(
      height: _height,
      child: Center(
        child: Obx(() {
          if (table.isPaging.value) {
            return const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSpinner(size: AppSpinnerSize.xs),
                SizedBox(width: AppSpacing.xs),
                Text('Loading more…', style: AppText.caption),
              ],
            );
          }
          if (table.hasPartialError.value) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Not everything loaded.', style: AppText.caption),
                const SizedBox(width: AppSpacing.xs),
                AppButton.text(label: 'Retry', onPressed: controller.reload),
              ],
            );
          }
          final total = table.total.value;
          if (table.isCapped.value && total > table.rows.length) {
            return Text(
              'Showing the first ${table.rows.length} of $total rows.',
              style: AppText.caption,
            );
          }
          return const SizedBox.shrink();
        }),
      ),
    );
  }
}

/// Opens the file viewer of a record; null when the screen has no file
/// repository (the chips are then plain).
SvFileOpener? _opener(BuildContext context, SmartViewController c) {
  if (!c.hasFiles) return null;
  return (files, index) =>
      SvFilePreviewDialog.show(context, c.newFilePreview(files, index));
}
