import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/form_option.dart';

/// Wraps a field box and opens a list's choices as a compact menu anchored
/// under it (or over it when there is no room below). One or several choices.
class FormChoiceMenu extends StatefulWidget {
  const FormChoiceMenu({
    super.key,
    required this.choices,
    required this.selected,
    required this.isMulti,
    required this.onDone,
    required this.builder,
  });

  static const searchFrom = 8;

  final List<FormChoice> choices;
  final List<String> selected;
  final bool isMulti;
  final ValueChanged<List<String>> onDone;
  final Widget Function(LayerLink link, Key boxKey, VoidCallback open) builder;

  @override
  State<FormChoiceMenu> createState() => _FormChoiceMenuState();
}

class _FormChoiceMenuState extends State<FormChoiceMenu> {
  final _link = LayerLink();
  final _boxKey = GlobalKey();
  final _picked = ValueNotifier<Set<String>>({});
  OverlayEntry? _entry;
  ModalRoute<dynamic>? _route;
  LocalHistoryEntry? _history;
  Set<String> _initial = {};
  bool _isUp = false;
  bool _isDisposing = false;

  bool get _hasSearch => widget.choices.length > FormChoiceMenu.searchFrom;

  double get _searchExtent =>
      _hasSearch ? AppSpacing.searchHeight + AppSpacing.xs * 2 : 0;

  double get _doneExtent => widget.isMulti ? AppSpacing.minTapTarget : 0;

  double get _cap =>
      AppSpacing.menuRowHeight * AppSpacing.menuMaxRows +
      _searchExtent +
      _doneExtent +
      AppSpacing.xxs * 2;

  @override
  void didUpdateWidget(FormChoiceMenu old) {
    super.didUpdateWidget(old);
    _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _close();
    _picked.dispose();
    super.dispose();
  }

  void _open() {
    if (_entry != null) return;
    _initial = {...widget.selected};
    _picked.value = {...widget.selected};
    _isUp = false;
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
    _route = ModalRoute.of(context);
    _history = LocalHistoryEntry(onRemove: _remove);
    _route?.addLocalHistoryEntry(_history!);
  }

  void _close() {
    final history = _history;
    if (history != null && _route != null) {
      _route!.removeLocalHistoryEntry(history);
    }
    _remove();
  }

  void _remove() {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    _history = null;
    entry.remove();
    entry.dispose();
    if (widget.isMulti &&
        !_isDisposing &&
        !setEquals(_picked.value, _initial)) {
      widget.onDone([
        for (final c in widget.choices)
          if (_picked.value.contains(c.value)) c.value,
      ]);
    }
  }

  void _pick(FormChoice c) {
    if (widget.isMulti) {
      final next = {..._picked.value};
      next.contains(c.value) ? next.remove(c.value) : next.add(c.value);
      _picked.value = next;
      return;
    }
    widget.onDone([c.value]);
    _close();
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return const SizedBox.shrink();
    }
    final mq = MediaQuery.of(overlayContext);
    final top = box.localToGlobal(Offset.zero).dy;
    final bottomEdge =
        mq.size.height -
        (mq.viewInsets.bottom > mq.padding.bottom
            ? mq.viewInsets.bottom
            : mq.padding.bottom) -
        AppSpacing.menuEdge;
    final below = bottomEdge - (top + box.size.height) - AppSpacing.menuGap;
    final above =
        top - mq.padding.top - AppSpacing.menuEdge - AppSpacing.menuGap;
    final natural = _naturalHeight();
    final fits = _isUp ? above >= natural : below >= natural;
    if (!fits) _isUp = above > below;
    final room = _isUp ? above : below;
    final maxHeight = room.clamp(AppSpacing.menuRowHeight, natural).toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            onVerticalDragStart: (_) => _close(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          width: box.size.width,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: _isUp ? Alignment.topLeft : Alignment.bottomLeft,
            followerAnchor: _isUp ? Alignment.bottomLeft : Alignment.topLeft,
            offset: Offset(0, _isUp ? -AppSpacing.menuGap : AppSpacing.menuGap),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: _MenuPanel(
                choices: widget.choices,
                picked: _picked,
                isMulti: widget.isMulti,
                hasSearch: _hasSearch,
                maxHeight: maxHeight,
                onPick: _pick,
                onDone: _close,
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _naturalHeight() {
    final rows = widget.choices.length * AppSpacing.menuRowHeight;
    final listed = _hasSearch
        ? AppSpacing.menuRowHeight * AppSpacing.menuMaxRows
        : rows;
    final h = listed + _searchExtent + _doneExtent + AppSpacing.xxs * 2;
    return h < _cap ? h : _cap;
  }

  @override
  Widget build(BuildContext context) => widget.builder(_link, _boxKey, _open);
}

class _MenuPanel extends StatefulWidget {
  const _MenuPanel({
    required this.choices,
    required this.picked,
    required this.isMulti,
    required this.hasSearch,
    required this.maxHeight,
    required this.onPick,
    required this.onDone,
  });

  final List<FormChoice> choices;
  final ValueNotifier<Set<String>> picked;
  final bool isMulti;
  final bool hasSearch;
  final double maxHeight;
  final ValueChanged<FormChoice> onPick;
  final VoidCallback onDone;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppDurations.fast,
      curve: AppCurves.out,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadius.controlAll,
          boxShadow: AppShadows.soft,
        ),
        child: Material(
          color: AppColors.background,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
            side: BorderSide(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.hasSearch)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: AppTextField(
                    controller: _search,
                    hint: 'Search',
                    minHeight: AppSpacing.searchHeight,
                    fillColor: AppColors.surface,
                    borderRadius: AppRadius.controlAll,
                    leading: const Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.muted,
                    ),
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
              Flexible(child: _list()),
              if (widget.isMulti) _doneRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    final shown = [
      for (final c in widget.choices)
        if (_query.isEmpty || c.label.toLowerCase().contains(_query)) c,
    ];
    if (shown.isEmpty) {
      return const SizedBox(
        height: AppSpacing.menuRowHeight,
        child: Center(child: Text('Nothing matches.', style: AppText.readable)),
      );
    }
    return ValueListenableBuilder<Set<String>>(
      valueListenable: widget.picked,
      builder: (context, picked, _) => Scrollbar(
        controller: _scroll,
        thickness: 3,
        radius: const Radius.circular(AppRadius.pill),
        child: ListView.builder(
          controller: _scroll,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final c = shown[i];
            final isOn = picked.contains(c.value);
            return InkWell(
              onTap: () => widget.onPick(c),
              child: Container(
                height: AppSpacing.menuRowHeight,
                color: isOn ? AppColors.accentSoft : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.controlPaddingX,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.input.copyWith(
                          fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (isOn)
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: AppColors.accent,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _doneRow() => InkWell(
    onTap: widget.onDone,
    child: Container(
      height: AppSpacing.minTapTarget,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: const Text('Done', style: AppText.action),
    ),
  );
}
