import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_refresh.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../data/models/record_state.dart';
import '../../../data/models/ticket.dart';
import '../tickets_texts.dart';
import 'ticket_history_timeline.dart';

/// The History panel: a soft sheet with its header and the events, newest
/// first. In the fixed layout it fills the rest of the screen and the list
/// scrolls inside it (pull to refresh works from the list); [isInline] is the
/// fallback, where the page itself scrolls and the panel is as tall as its
/// events, at least [minHeight].
class TicketHistoryPanel extends StatefulWidget {
  const TicketHistoryPanel({
    super.key,
    required this.history,
    required this.state,
    required this.ticket,
    required this.nameOf,
    required this.onRefresh,
    this.first,
    this.isInline = false,
  });

  final RecordHistory? history;
  final AppViewState state;
  final Ticket ticket;
  final String? first;
  final String Function(String user) nameOf;
  final Future<void> Function() onRefresh;
  final bool isInline;

  /// The least height the panel gets before the page scrolls instead.
  static const minHeight = 160.0;

  @override
  State<TicketHistoryPanel> createState() => _TicketHistoryPanelState();
}

class _TicketHistoryPanelState extends State<TicketHistoryPanel> {
  List<RecordEvent> _shown = const [];
  Set<int> _fresh = {};
  bool _isFirst = true;
  bool _isAtTop = true;

  List<RecordEvent> get _incoming => widget.history?.events ?? const [];

  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(TicketHistoryPanel old) {
    super.didUpdateWidget(old);
    final known = {for (final e in _shown) e.id};
    final hasNew = _incoming.any((e) => !known.contains(e.id));
    // While the user is down the list, a new event waits at the top: the
    // list keeps its place and shows it when the user is back at the top.
    if (hasNew && !_isAtTop && !widget.isInline) return;
    _apply();
  }

  void _apply() {
    final known = {for (final e in _shown) e.id};
    _fresh = _isFirst
        ? {}
        : {
            for (final e in _incoming)
              if (!known.contains(e.id)) e.id,
          };
    _isFirst = false;
    _shown = _incoming;
    if (_fresh.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fresh = {});
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final isAtTop = n.metrics.pixels <= 1;
    if (isAtTop == _isAtTop) return false;
    _isAtTop = isAtTop;
    final known = {for (final e in _shown) e.id};
    if (isAtTop && _incoming.any((e) => !known.contains(e.id))) {
      setState(_apply);
    }
    return false;
  }

  HistoryFeed _feed() => HistoryFeed(
    history: widget.history!,
    nameOf: widget.nameOf,
    ticket: widget.ticket,
    first: widget.first,
    events: _shown,
  );

  @override
  Widget build(BuildContext context) {
    final count = widget.history?.events.length ?? 0;
    return DecoratedBox(
      decoration: const ShapeDecoration(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
          side: BorderSide(color: AppColors.line),
        ),
      ),
      child: widget.isInline
          ? ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TicketHistoryPanel.minHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(count: count),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.page,
                      AppSpacing.xs,
                      AppSpacing.page,
                      AppSpacing.xl,
                    ),
                    child: _inlineBody(),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(count: count),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: Scrollbar(
                      child: AppRefresh(
                        onRefresh: widget.onRefresh,
                        slivers: _slivers(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  bool get _hasEvents => widget.history != null && _shown.isNotEmpty;

  Widget _inlineBody() {
    if (_hasEvents) {
      return TicketHistoryTimeline(feed: _feed(), freshIds: _fresh);
    }
    return _Notice(state: widget.state, onRetry: widget.onRefresh);
  }

  List<Widget> _slivers(BuildContext context) {
    if (!_hasEvents) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Notice(state: widget.state, onRetry: widget.onRefresh),
        ),
      ];
    }
    final feed = _feed();
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.xs,
          AppSpacing.page,
          AppSpacing.md + bottom,
        ),
        sliver: SliverList.builder(
          itemCount: feed.events.length,
          itemBuilder: (context, i) => TicketHistoryItem(
            key: ValueKey(feed.events[i].id),
            feed: feed,
            index: i,
            isFresh: _fresh.contains(feed.events[i].id),
          ),
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    label: '${TicketsTexts.historyTitle}, ${TicketsTexts.eventCount(count)}',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.xxs,
      ),
      child: Row(
        children: [
          const Flexible(
            child: Text(TicketsTexts.historyTitle, style: AppText.subtitle),
          ),
          if (count > 0) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppTones.slate.tint,
                borderRadius: AppRadius.pillAll,
              ),
              child: Text(
                '$count',
                style: AppText.label.copyWith(
                  color: AppTones.slate.strong,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The panel without events: loading, a calm "No history yet", or the error
/// with a way to try again.
class _Notice extends StatelessWidget {
  const _Notice({required this.state, required this.onRetry});

  final AppViewState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (state == AppViewState.loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: AppSpinner()),
      );
    }
    final isFailed = state == AppViewState.error;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isFailed ? TicketsTexts.historyError : TicketsTexts.historyEmpty,
            style: AppText.readable,
            textAlign: TextAlign.center,
          ),
          if (isFailed)
            AppButton.text(
              label: TicketsTexts.historyRetry,
              onPressed: () => onRetry(),
            ),
        ],
      ),
    );
  }
}
