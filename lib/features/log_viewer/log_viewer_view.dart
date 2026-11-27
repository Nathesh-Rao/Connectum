import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import 'log_viewer_controller.dart';
import 'log_viewer_prefs.dart';

/// The log file read inside the app. Header and states follow the Smart View
/// file preview; the body is [SvLogViewer].
class LogViewerView extends GetView<LogViewerController> {
  const LogViewerView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      isScrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          _Header(controller: c),
          Obx(
            () => c.isSearching.value
                ? _SearchBar(controller: c)
                : const SizedBox.shrink(),
          ),
          const Divider(height: 1, thickness: 1, color: AppSv.hairline),
          Expanded(
            child: Obx(
              () => AppStateView(
                state: c.viewState.value,
                emptyTitle: 'No log entries yet',
                errorMessage: c.errorText.value.isEmpty
                    ? "The log file couldn't be read."
                    : "The log file couldn't be read.\n${c.errorText.value}",
                onRetry: c.load,
                child: _Body(controller: c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => Column(
        children: [
          if (c.doc.value.isPartial)
            Container(
              width: double.infinity,
              color: AppColors.violetTint,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: const Text(
                'Showing last part of file',
                key: ValueKey('log-partial'),
                style: AppText.supporting,
              ),
            ),
          Expanded(child: _lines(c)),
        ],
      ),
    );
  }

  Widget _lines(LogViewerController c) {
    return SvLogViewer(
      doc: c.doc.value,
      scroll: c.scroll,
      isWrap: c.isWrap.value,
      fontSize: c.size.value.fontSize,
      hitStarts: c.hitStarts,
      queryLength: c.queryLength,
      currentHit: c.hits.value.hits.isEmpty ? null : c.currentHit,
      onRows: (rows, extent) {
        c.rows = rows;
        c.lineExtent = extent;
      },
      onTop: c.jumpToTop,
      onLatest: c.jumpToLatest,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SizedBox(
      height: AppSv.fileBarHeight,
      child: Row(
        children: [
          const SizedBox(width: AppSpacing.xxs),
          AppButton.icon(
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: Get.back,
          ),
          Expanded(
            child: Obx(
              () => Text(
                c.fileName.value.isEmpty ? 'Log file' : c.fileName.value,
                key: const ValueKey('log-title'),
                style: AppSv.fileTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          AppButton.icon(
            key: const ValueKey('log-search'),
            icon: Icons.search,
            semanticLabel: 'Search',
            onPressed: c.toggleSearch,
          ),
          AppButton.icon(
            key: const ValueKey('log-refresh'),
            icon: Icons.refresh,
            semanticLabel: 'Refresh',
            onPressed: () => c.load(isRefresh: true),
          ),
          AppButton.icon(
            key: const ValueKey('log-share'),
            icon: Icons.ios_share_outlined,
            semanticLabel: 'Share',
            onPressed: c.share,
          ),
          Obx(() {
            final isWrap = c.isWrap.value;
            final size = c.size.value;
            return PopupMenuButton<String>(
              key: const ValueKey('log-menu'),
              tooltip: 'More',
              icon: const Icon(Icons.more_vert, color: AppColors.ink),
              color: AppColors.white,
              onSelected: (v) {
                switch (v) {
                  case 'save':
                    c.saveToDevice();
                  case 'wrap':
                    c.setWrap(!c.isWrap.value);
                  default:
                    final picked = LogTextSize.values.firstWhereOrNull(
                      (s) => s.name == v,
                    );
                    if (picked != null) c.setSize(picked);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'save',
                  child: Text('Save to device'),
                ),
                CheckedPopupMenuItem(
                  value: 'wrap',
                  checked: isWrap,
                  child: const Text('Wrap lines'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  enabled: false,
                  child: Text('Text size', style: AppText.supporting),
                ),
                for (final s in LogTextSize.values)
                  CheckedPopupMenuItem(
                    value: s.name,
                    checked: size == s,
                    child: Text(s.label),
                  ),
              ],
            );
          }),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final LogViewerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.xxs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: AppSearchField(
              hint: 'Find in log',
              controller: c.searchField,
              focusNode: c.searchFocus,
              onChanged: c.onQuery,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Obx(() {
            final n = c.hits.value.hits.length;
            final label = c.searchField.text.isEmpty
                ? ''
                : c.isFinding.value
                ? '…'
                : n == 0
                ? '0'
                : '${c.current.value + 1}/$n${c.hits.value.isCut ? '+' : ''}';
            return Semantics(
              liveRegion: true,
              child: Text(
                label,
                key: const ValueKey('log-match-count'),
                style: AppText.supporting,
              ),
            );
          }),
          AppButton.icon(
            icon: Icons.keyboard_arrow_up,
            semanticLabel: 'Previous match',
            onPressed: c.previousHit,
          ),
          AppButton.icon(
            icon: Icons.keyboard_arrow_down,
            semanticLabel: 'Next match',
            onPressed: c.nextHit,
          ),
          AppButton.icon(
            icon: Icons.close,
            semanticLabel: 'Close search',
            onPressed: c.closeSearch,
          ),
        ],
      ),
    );
  }
}
