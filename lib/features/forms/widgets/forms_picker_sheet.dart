import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import '../forms_picker_controller.dart';
import 'form_chip.dart';
import 'form_chip_section.dart';

/// The forms button's sheet: search, the forms as chips, the options that are
/// not available on mobile, and a pinned bar with My Submissions.
class FormsPickerSheet extends StatelessWidget {
  const FormsPickerSheet({super.key, required this.controller});

  static const int collapseAfter = 12;

  final FormsPickerController controller;

  static Future<void> show(
    BuildContext context,
    FormsPickerController controller,
  ) {
    controller.prepare();
    return AppBottomSheet.showPinned<void>(
      context,
      child: FormsPickerSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    AppStateImage.precache(context, const [
      AppStateImageKind.emptyGeneric,
      AppStateImageKind.error,
      AppStateImageKind.offline,
      AppStateImageKind.noResults,
    ], size: AppSpacing.stateImageSmall);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSheetHeader(
          title: 'Forms',
          subtitle: 'Choose a form to fill in',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: AppSearchField(
            controller: c.queryField,
            hint: 'Search forms',
            onChanged: (v) => c.query.value = v,
          ),
        ),
        Flexible(
          child: Obx(() {
            final state = c.viewState;
            if (state != AppViewState.content) {
              return SizedBox(
                height: 300,
                child: AppStateView(
                  state: state,
                  emptyTitle: 'No forms for you yet',
                  emptyMessage: 'Forms you can fill show up here.',
                  errorMessage: "We couldn't load your forms.",
                  onRetry: c.options.refresh,
                  loadingChild: const _Skeleton(),
                  child: const SizedBox.shrink(),
                ),
              );
            }
            return _Content(controller: c);
          }),
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.controller});

  final FormsPickerController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final c = controller;
    final isSearching = c.query.value.trim().isNotEmpty;
    final recents = isSearching ? const <FormOption>[] : c.recentOptions;
    final shown = c.shown;
    final available = [
      for (final o in shown)
        if (c.isAvailable(o)) o,
    ];
    final unavailable = [
      for (final o in shown)
        if (!c.isAvailable(o)) o,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LinkStatus(controller: c),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: shown.isEmpty
                ? const _NoResults()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (recents.isNotEmpty) ...[
                        FormChipSection(
                          label: 'Recent',
                          chips: [
                            for (final o in recents)
                              FormChip(
                                label: o.caption,
                                icon: Icons.history,
                                tintKey: o.id,
                                semanticsLabel: 'Open ${o.caption}',
                                onTap: () {
                                  Navigator.of(context).pop();
                                  c.open(o);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (available.isNotEmpty)
                        FormChipSection(
                          label: 'Forms',
                          collapseAfter: isSearching
                              ? null
                              : FormsPickerSheet.collapseAfter,
                          chips: [
                            for (final o in available)
                              FormChip(
                                label: o.caption,
                                icon: c.iconOf(o),
                                tintKey: o.id,
                                onTap: o.isLink
                                    ? () => c.openLink(
                                        o,
                                        closeSheet: () =>
                                            Navigator.of(context).pop(),
                                      )
                                    : () {
                                        Navigator.of(context).pop();
                                        c.open(o);
                                      },
                              ),
                          ],
                        ),
                      if (unavailable.isNotEmpty) ...[
                        if (available.isNotEmpty) const _DashedDivider(),
                        FormChipSection(
                          label: 'Not available on mobile yet',
                          chips: [
                            for (final o in unavailable)
                              FormChip(
                                label: o.caption,
                                icon: Icons.link,
                                tintKey: o.id,
                                semanticsLabel:
                                    '${o.caption}, not available on mobile',
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        _BottomBar(
          count: available.length,
          onMySubmissions: () {
            Navigator.of(context).pop();
            c.openMySubmissions();
          },
        ),
      ],
    );
  });
}

class _LinkStatus extends StatelessWidget {
  const _LinkStatus({required this.controller});

  final FormsPickerController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final c = controller;
    final notice = c.linkNotice.value;
    if (c.isLinkOpening.value) {
      return const LinearProgressIndicator(
        minHeight: 2,
        color: AppColors.primary,
        backgroundColor: AppColors.line,
      );
    }
    if (notice == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                notice,
                style: const TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: AppText.sizeReadable,
                  height: 1.3,
                  color: AppColors.error,
                ),
              ),
            ),
            if (c.linkToCopy.value != null)
              TextButton(
                onPressed: c.copyLinkToClipboard,
                child: const Text('Copy link'),
              ),
          ],
        ),
      ),
    );
  });
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.count, required this.onMySubmissions});

  final int count;
  final VoidCallback onMySubmissions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom > 0 ? 0.0 : media.padding.bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xs + inset,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$count',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    TextSpan(text: count == 1 ? ' form' : ' forms'),
                  ],
                ),
                style: const TextStyle(
                  fontFamily: AppText.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ),
            TextButton(
              onPressed: onMySubmissions,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSpacing.minTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                foregroundColor: AppColors.primary,
                overlayColor: AppColors.primary,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.mdAll,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppPngIcon(
                    asset: AppIcons.bottomNav.submissionsUnselected,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xxs + 2),
                  const Text(
                    'My Submissions',
                    style: TextStyle(
                      fontFamily: AppText.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: AppColors.primary.withAlpha(150),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: SizedBox(
      height: 1,
      child: CustomPaint(painter: _DashPainter(), size: Size.fromHeight(1)),
    ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_off, size: 28, color: AppColors.muted),
        SizedBox(height: AppSpacing.xs),
        Text(
          'No forms found',
          style: TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
        SizedBox(height: AppSpacing.xxs),
        Text(
          'Try a different name',
          style: TextStyle(
            fontFamily: AppText.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.muted,
          ),
        ),
      ],
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => AppSkeletonScope(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (var i = 0; i < 8; i++)
            AppSkeleton(
              width: 80.0 + (i % 3) * 30,
              height: FormChip.height,
              radius: AppRadius.pill,
            ),
        ],
      ),
    ),
  );
}
