import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/log/safe.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_inbox.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_text_field.dart';
import '../inbox_controller.dart';
import 'inbox_icon_button.dart';
import 'inbox_views_sheet.dart';
import '../models/approval_quick_filter.dart';
import 'approval_filter_bar.dart';
import 'inbox_filter_sheet.dart';

/// One app bar row: the title, the open view as a chip (Records tab), then
/// the search and filter round buttons. The search opens leftwards into a full
/// width pill over the row; a result count line shows under it once there is a
/// query.
class InboxHeader extends StatefulWidget {
  const InboxHeader({super.key, required this.controller});

  final InboxController controller;

  @override
  State<InboxHeader> createState() => _InboxHeaderState();
}

class _InboxHeaderState extends State<InboxHeader>
    with SingleTickerProviderStateMixin {
  static const _focusAt = 0.85;

  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: AppDurations.searchToggle,
    value: widget.controller.isSearchOpen.value ? 1 : 0,
  );
  late final Worker _follow;
  bool _isFocusDone = false;

  @override
  void initState() {
    super.initState();
    _isFocusDone = _ctl.value >= _focusAt;
    _ctl.addListener(_focusWhenOpen);
    _follow = ever(widget.controller.isSearchOpen, _onOpenChanged);
  }

  void _onOpenChanged(bool isOpen) {
    if (!mounted) return;
    if (isOpen) {
      _isFocusDone = false;
      fireAndLog('inbox_header', () => _ctl.forward());
    } else {
      fireAndLog('inbox_header', () => _ctl.reverse());
    }
  }

  void _focusWhenOpen() {
    if (_isFocusDone || _ctl.value < _focusAt) return;
    _isFocusDone = true;
    if (widget.controller.isSearchOpen.value) {
      widget.controller.searchFocus.requestFocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctl.duration = MediaQuery.disableAnimationsOf(context)
        ? AppDurations.reduced
        : AppDurations.searchToggle;
  }

  @override
  void dispose() {
    _follow.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final isStill = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppInbox.searchHeight),
            child: AnimatedBuilder(
              animation: _ctl,
              builder: (context, _) => Stack(
                alignment: AlignmentDirectional.centerEnd,
                children: [
                  _TitleRow(controller: c, t: _ctl.value, isStill: isStill),
                  if (_ctl.value > 0 || c.isSearchOpen.value)
                    Positioned.fill(
                      child: _SearchLayer(
                        controller: c,
                        t: _ctl.value,
                        isStill: isStill,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _ResultCount(controller: c),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.controller,
    required this.t,
    required this.isStill,
  });

  final InboxController controller;

  /// The search's linear progress, 0 closed to 1 open.
  final double t;
  final bool isStill;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isBusy = t > 0 || c.isSearchOpen.value;
    final fade = isStill ? 1 - t : 1 - const Interval(0, 0.5).transform(t);
    final buttonsFade = isStill
        ? 1 - t
        : 1 - const Interval(0, 0.35).transform(t);
    final slide = isStill
        ? 0.0
        : -AppDistances.enter * AppCurves.out.transform(t);
    return IgnorePointer(
      ignoring: isBusy,
      child: ExcludeSemantics(
        excluding: isBusy,
        child: Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: fade,
                child: Transform.translate(
                  offset: Offset(slide, 0),
                  child: Row(
                    children: [
                      Text(
                        InboxController.title,
                        style: AppText.heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: AppInbox.titleMaxScale),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                          child: Align(
                            alignment: Alignment.center,
                            child: LayoutBuilder(
                              builder: (context, box) =>
                                  box.maxWidth < AppInbox.viewChipMinWidth
                                  ? const SizedBox.shrink()
                                  : _ViewChip(controller: c),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Opacity(
              opacity: buttonsFade,
              child: KeyedSubtree(
                key: c.tour?.buttonsKey,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InboxIconButton(
                      icon: Icons.search_rounded,
                      label: 'Search',
                      tone: AppInbox.searchTone,
                      onPressed: c.openSearch,
                    ),
                    Obx(() {
                      final isApprovals = c.isApprovalsOpen;
                      final n = isApprovals
                          ? ApprovalQuick.selectedOf(
                              c.approvals.primary.value,
                              c.approvals.side.value,
                              c.approvals.panel.value.entries,
                            ).length
                          : c.filterCount;
                      return InboxIconButton(
                        key: ValueKey(
                          isApprovals ? 'approvals-filter' : 'filter',
                        ),
                        icon: Icons.tune_rounded,
                        label: isApprovals
                            ? (n > 0
                                  ? 'Filter the approvals, $n set'
                                  : 'Filter the approvals')
                            : (n > 0
                                  ? 'Filter and sort, $n set'
                                  : 'Filter and sort'),
                        count: n,
                        isActive: n > 0,
                        tone: AppInbox.filterTone,
                        onPressed: () => isApprovals
                            ? ApprovalFilterPopup.show(context, c.approvals)
                            : InboxFilterSheet.show(context, c),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The search over the title row: the field grows leftwards from the search
/// button's place, and the close circle sits where the filter button was,
/// above it, with a full 44 dp hit area.
class _SearchLayer extends StatelessWidget {
  const _SearchLayer({
    required this.controller,
    required this.t,
    required this.isStill,
  });

  final InboxController controller;
  final double t;
  final bool isStill;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isOpen = c.isSearchOpen.value;
    final dir = Directionality.of(context);
    final iconT = isStill
        ? 1.0
        : const Interval(0.2, 1, curve: AppCurves.out).transform(t);
    final hintT = isStill ? 1.0 : const Interval(0.5, 1).transform(t);
    final closeT = isStill
        ? 1.0
        : const Interval(0.4, 1, curve: AppCurves.out).transform(t);
    final eased = AppCurves.out.transform(t);
    return LayoutBuilder(
      builder: (context, box) {
        final fieldW = (box.maxWidth - AppInbox.hit).clamp(0.0, box.maxWidth);
        final w = isStill
            ? fieldW
            : (AppInbox.hit + (fieldW - AppInbox.hit) * eased).clamp(
                0.0,
                fieldW,
              );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            PositionedDirectional(
              start: 0,
              end: AppInbox.hit,
              top: 0,
              bottom: 0,
              child: Opacity(
                opacity: isStill ? t : 1,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ClipRRect(
                    borderRadius: AppRadius.pillAll,
                    child: SizedBox(
                      width: w,
                      child: OverflowBox(
                        alignment: AlignmentDirectional.centerStart,
                        minWidth: fieldW,
                        maxWidth: fieldW,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: _SearchField(
                          controller: c,
                          iconT: iconT,
                          hintT: hintT,
                          textDirection: dir,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              width: AppInbox.hit,
              child: IgnorePointer(
                ignoring: !isOpen,
                child: Opacity(
                  opacity: closeT.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * closeT,
                    child: Semantics(
                      button: true,
                      label: 'Close search',
                      excludeSemantics: true,
                      child: Tooltip(
                        message: 'Close search',
                        excludeFromSemantics: true,
                        child: GestureDetector(
                          key: const ValueKey('inbox-search-close'),
                          behavior: HitTestBehavior.opaque,
                          onTap: c.closeSearch,
                          child: const SizedBox(
                            width: AppInbox.hit,
                            height: AppInbox.hit,
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppInbox.closeFill,
                                  shape: BoxShape.circle,
                                ),
                                child: SizedBox(
                                  width: AppInbox.closeDisc,
                                  height: AppInbox.closeDisc,
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: AppInbox.discIcon,
                                    color: AppInbox.closeInk,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The pill field: a soft tinted fill, a primary ring while focused, the
/// search icon turning in, the hint fading in and a × that appears only
/// with text.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.iconT,
    required this.hintT,
    required this.textDirection,
  });

  final InboxController controller;
  final double iconT;
  final double hintT;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c.searchFocus,
      builder: (context, _) => AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppCurves.out,
        decoration: BoxDecoration(
          borderRadius: AppRadius.pillAll,
          boxShadow: c.searchFocus.hasFocus ? AppShadows.focusRing : const [],
        ),
        child: AppTextField(
          controller: c.searchField,
          focusNode: c.searchFocus,
          hint: hintT > 0 ? InboxController.searchNote : null,
          minHeight: AppInbox.searchHeight,
          fillColor: AppInbox.searchFill,
          borderColor: AppInbox.searchRing,
          focusBorderColor: AppColors.primary,
          borderRadius: AppRadius.pillAll,
          horizontalPadding: AppSpacing.sm,
          textStyle: AppText.body,
          textInputAction: TextInputAction.search,
          onChanged: c.onQueryChanged,
          leading: Transform.rotate(
            angle:
                (1 - iconT) *
                -math.pi /
                2 *
                (textDirection == TextDirection.ltr ? 1 : -1),
            child: Opacity(
              opacity: iconT.clamp(0.0, 1.0),
              child: const Icon(
                Icons.search_rounded,
                size: AppInbox.discIcon,
                color: AppInbox.discInk,
              ),
            ),
          ),
          suffix: _ClearButton(controller: c),
        ),
      ),
    );
  }
}

/// The × inside the field: scales and fades in only while there is text.
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: c.searchField,
      builder: (context, v, _) {
        final hasText = v.text.isNotEmpty;
        return AnimatedSwitcher(
          duration: AppDurations.fast,
          switchInCurve: AppCurves.out,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: a, child: child),
          ),
          child: hasText
              ? Semantics(
                  key: const ValueKey('inbox-search-clear'),
                  button: true,
                  label: 'Clear search',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      c.clearSearch();
                      c.searchFocus.requestFocus();
                    },
                    child: const SizedBox(
                      width: AppInbox.hit,
                      height: AppInbox.closeDisc,
                      child: Icon(
                        Icons.close_rounded,
                        size: AppInbox.discIcon - 2,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('inbox-search-no-clear')),
        );
      },
    );
  }
}

/// "12 results" under the field, animated in once there is a query.
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final isShown = c.isSearchOpen.value && c.activeQuery.isNotEmpty;
      final n = c.isApprovalsOpen
          ? c.approvals.rows.length
          : c.rows.length + (c.hasApprovalsPart ? c.approvalCards.length : 0);
      final text = n == 0
          ? 'No results'
          : n == 1
          ? '1 result'
          : '$n results';
      return AnimatedSize(
        duration: AppDurations.fast,
        curve: AppCurves.out,
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          duration: AppDurations.fast,
          opacity: isShown ? 1 : 0,
          child: isShown
              ? Padding(
                  key: const ValueKey('inbox-search-count'),
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.page + AppSpacing.sm,
                    end: AppSpacing.page,
                    bottom: AppSpacing.xs,
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(text, style: AppText.caption),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      );
    });
  }
}

/// The open view's name as a chip between the title and the buttons; a dot says the screen
/// differs from the saved view. Opens the Views panel. Shrinks with an
/// ellipsis; hidden on the Approvals tab.
class _ViewChip extends StatelessWidget {
  const _ViewChip({required this.controller});

  final InboxController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final name = c.views.openName;
      final isChanged = c.isViewChanged;
      return AnimatedSize(
        duration: AppDurations.fast,
        curve: AppCurves.out,
        alignment: Alignment.center,
        child: c.isApprovalsOpen
            ? const SizedBox.shrink()
            : KeyedSubtree(
                key: c.tour?.viewsKey,
                child: Semantics(
                  button: true,
                  label: isChanged ? 'Views, $name, changed' : 'Views, $name',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => InboxViewsSheet.show(context, c),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AppInbox.viewChipHeight,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppInbox.viewChipFill,
                          borderRadius: AppRadius.pillAll,
                          border: Border.all(color: AppInbox.viewChipBorder),
                        ),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: AppSpacing.sm,
                            end: AppSpacing.xs,
                            top: AppSpacing.xxs,
                            bottom: AppSpacing.xxs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.filter_center_focus_rounded,
                                size: AppInbox.tabIcon,
                                color: AppInbox.discInk,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.readableStrong.copyWith(
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              if (isChanged) ...[
                                const SizedBox(width: AppSpacing.xs),
                                const DecoratedBox(
                                  key: ValueKey('view-changed'),
                                  decoration: BoxDecoration(
                                    color: AppInbox.changedDot,
                                    shape: BoxShape.circle,
                                  ),
                                  child: SizedBox(
                                    width: AppSpacing.xs,
                                    height: AppSpacing.xs,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xxs),
                                Flexible(
                                  child: Text(
                                    'changed',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: AppText.caption,
                                  ),
                                ),
                              ],
                              const SizedBox(width: AppSpacing.xxs),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: AppInbox.discIcon,
                                color: AppColors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
    });
  }
}
