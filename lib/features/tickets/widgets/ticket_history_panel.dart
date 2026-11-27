import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/app_state_view.dart';
import '../../../data/models/record_state.dart';
import '../../../data/models/ticket.dart';
import '../tickets_texts.dart';
import 'ticket_history_timeline.dart';

/// The History panel: a soft sheet with its header and the events, newest
/// first, as tall as its events (at least [minHeight]); the page scrolls.
class TicketHistoryPanel extends StatefulWidget {
  const TicketHistoryPanel({
    super.key,
    required this.history,
    required this.state,
    required this.ticket,
    required this.nameOf,
    required this.onRefresh,
    this.first,
    this.pictureOf,
  });

  final RecordHistory? history;
  final AppViewState state;
  final Ticket ticket;
  final String? first;
  final String? Function(String user)? pictureOf;
  final String Function(String user) nameOf;
  final Future<void> Function() onRefresh;

  /// The least height the panel gets before the page scrolls instead.
  static const minHeight = 160.0;

  @override
  State<TicketHistoryPanel> createState() => _TicketHistoryPanelState();
}

class _TicketHistoryPanelState extends State<TicketHistoryPanel> {
  List<RecordEvent> _shown = const [];
  Set<int> _fresh = {};
  bool _isFirst = true;

  List<RecordEvent> get _incoming => widget.history?.events ?? const [];

  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(TicketHistoryPanel old) {
    super.didUpdateWidget(old);
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

  HistoryFeed _feed() => HistoryFeed(
    history: widget.history!,
    nameOf: widget.nameOf,
    ticket: widget.ticket,
    first: widget.first,
    pictureOf: widget.pictureOf,
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
      child: ConstrainedBox(
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
              child: _body(),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasEvents => widget.history != null && _shown.isNotEmpty;

  Widget _body() {
    if (_hasEvents) {
      return TicketHistoryTimeline(feed: _feed(), freshIds: _fresh);
    }
    return _Notice(state: widget.state, onRetry: widget.onRefresh);
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
