import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import '../models/ticket_text.dart';
import '../tickets_texts.dart';
import 'history_parts.dart';
import 'ticket_status_pill.dart';

/// What the timeline draws: the events newest first, the names, and the
/// completion each event came from (the nearest older event that had one).
class HistoryFeed {
  HistoryFeed({
    required this.history,
    required this.nameOf,
    required this.ticket,
    this.first,
    this.pictureOf,
    List<RecordEvent>? events,
    DateTime? now,
  }) : now = now ?? DateTime.now(),
       events = List.unmodifiable((events ?? history.events).reversed) {
    int? last;
    for (final e in (events ?? history.events)) {
      final percent = int.tryParse(e.completion);
      if (percent == null) continue;
      if (last != null) _previous[e.id] = last;
      last = percent;
    }
  }

  final RecordHistory history;
  final String Function(String user) nameOf;
  final Ticket ticket;

  /// The status a record starts at, for the tone of a status pill.
  final String? first;

  /// A person's picture address, for the small face beside the name.
  final String? Function(String user)? pictureOf;
  final DateTime now;

  /// Newest first. Ids stay as the server sent them.
  final List<RecordEvent> events;

  final Map<int, int> _previous = {};

  int? previousCompletion(RecordEvent e) => _previous[e.id];

  String who(String user) => user.isEmpty ? user : nameOf(history.nameOf(user));
}

/// The kind of an event: its icon and its tone. An unknown op is a neutral
/// dot.
class HistoryKind {
  const HistoryKind(this.icon, this.tone);

  final IconData? icon;
  final AppTone tone;

  static HistoryKind of(String op) => switch (op) {
    'created' => const HistoryKind(Icons.add, AppTones.primary),
    'edited' => const HistoryKind(Icons.edit_outlined, AppTones.primary),
    'deleted' => const HistoryKind(Icons.delete_outline, AppTones.red),
    'sent_for_approval' => const HistoryKind(
      Icons.outbox_outlined,
      AppTones.violet,
    ),
    'waiting' => const HistoryKind(Icons.hourglass_empty, AppTones.violet),
    'approved' => const HistoryKind(Icons.check, AppTones.green),
    'declined' => const HistoryKind(Icons.close, AppTones.red),
    'returned' => const HistoryKind(Icons.undo, AppTones.violet),
    'resubmitted' => const HistoryKind(Icons.replay, AppTones.primary),
    'approved_final' => const HistoryKind(
      Icons.verified_outlined,
      AppTones.green,
    ),
    'sent' => const HistoryKind(Icons.send_outlined, AppTones.primary),
    'status' => const HistoryKind(Icons.flag_outlined, AppTones.violet),
    'reassigned' => const HistoryKind(Icons.swap_horiz, AppTones.primary),
    _ => const HistoryKind(null, AppTones.slate),
  };
}

/// The events of a record as one non-scrolling column, newest first.
class TicketHistoryTimeline extends StatelessWidget {
  const TicketHistoryTimeline({
    super.key,
    required this.feed,
    this.freshIds = const {},
  });

  final HistoryFeed feed;
  final Set<int> freshIds;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < feed.events.length; i++)
        TicketHistoryItem(
          key: ValueKey(feed.events[i].id),
          feed: feed,
          index: i,
          isFresh: freshIds.contains(feed.events[i].id),
        ),
    ],
  );
}

/// One event: a dot on the rail, a title, who and when, and what it carried.
class TicketHistoryItem extends StatelessWidget {
  const TicketHistoryItem({
    super.key,
    required this.feed,
    required this.index,
    this.isFresh = false,
  });

  final HistoryFeed feed;
  final int index;
  final bool isFresh;

  static const dot = 28.0;

  @override
  Widget build(BuildContext context) {
    final e = feed.events[index];
    final isNewest = index == 0;
    final isLast = index == feed.events.length - 1;
    final kind = HistoryKind.of(e.op);
    final who = feed.who;

    final to = [for (final u in e.to) who(u)];
    final toTitle = to.isEmpty
        ? ''
        : to.length == 1
        ? to.first
        : '${to.first} ${TicketsTexts.plusCount(to.length - 1)}';
    final title = TicketsTexts.opTitle(e.op, to: toTitle, via: e.via);

    final hasMove = e.fromStatus.isNotEmpty || e.toStatus.isNotEmpty;
    final fromHolder = e.fromHolder.isNotEmpty ? e.fromHolder : e.by;
    final hasPeople = to.isNotEmpty && (e.op == 'sent' || e.op == 'reassigned');
    final percent = int.tryParse(e.completion);
    final before = feed.previousCompletion(e);
    final fileNames = [
      for (final id in e.files) feed.history.files[id]?.name ?? id,
    ];
    final changes = [
      for (final c in e.changes)
        (feed.history.fields[c.field] ?? c.field, c.from, c.to),
    ];
    final ago = TicketText.ago(e.ts, feed.now);
    final exact = e.ts <= 0
        ? ''
        : '${ChatTime.date(e.ts)}, ${ChatTime.time(e.ts)}';

    final body = Padding(
      padding: const EdgeInsets.only(
        left: dot + AppSpacing.sm,
        bottom: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(title, style: AppText.bodyStrong),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                if (e.by.isNotEmpty) ...[
                  AppAvatar(
                    name: who(e.by),
                    size: AppSpacing.chipAvatar,
                    picture: feed.pictureOf?.call(e.by),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: AppText.rowCaption,
                      children: [
                        TextSpan(
                          text: [
                            who(e.by),
                            if (e.isAsAdmin) TicketsTexts.byAdmin,
                            if (e.isClaimed) TicketsTexts.claimed,
                          ].where((s) => s.isNotEmpty).join(' · '),
                        ),
                        if (ago.isNotEmpty) ...[
                          const TextSpan(text: ' · '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: Tooltip(
                              message: exact,
                              triggerMode: TooltipTriggerMode.tap,
                              child: Text(ago, style: AppText.rowCaption),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasMove)
            _Row(
              child: Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (e.fromStatus.isNotEmpty)
                    HistoryStatus(
                      label: e.fromStatus,
                      tone: AppTones.slate,
                      isMuted: true,
                    ),
                  if (e.fromStatus.isNotEmpty && e.toStatus.isNotEmpty)
                    const HistoryArrow(),
                  if (e.toStatus.isNotEmpty)
                    HistoryStatus(
                      label: e.toStatus,
                      tone: TicketStatusPill.toneOfStatus(
                        e.toStatus,
                        isFinal: e.isFinal,
                        first: feed.first,
                      ),
                      isFinal: e.isFinal,
                    ),
                ],
              ),
            ),
          if (hasPeople)
            _Row(
              child: HistoryPeople(
                from: e.op == 'sent' ? who(fromHolder) : '',
                to: to,
              ),
            ),
          if (percent != null || e.hours.isNotEmpty)
            _Row(
              child: Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (percent != null) ...[
                    if (before != null && before != percent) ...[
                      HistoryCompletion(percent: before, isMuted: true),
                      const HistoryArrow(),
                    ],
                    HistoryCompletion(percent: percent),
                  ],
                  if (e.hours.isNotEmpty)
                    TicketPill(
                      label: TicketsTexts.hoursValue(e.hours),
                      icon: Icons.schedule,
                      tone: AppTones.slate,
                    ),
                ],
              ),
            ),
          if (e.reason.isNotEmpty)
            _Row(
              child: HistoryQuote(
                storageKey: 'h-${e.id}-reason',
                text: e.reason,
                label: TicketsTexts.reasonLabel,
              ),
            ),
          if (e.remarks.isNotEmpty)
            _Row(
              child: HistoryQuote(
                storageKey: 'h-${e.id}-remarks',
                text: e.remarks,
              ),
            ),
          if (changes.isNotEmpty) _Row(child: HistoryChanges(rows: changes)),
          if (fileNames.isNotEmpty) _Row(child: HistoryFiles(names: fileNames)),
        ],
      ),
    );

    final item = Stack(
      children: [
        if (!isLast)
          const Positioned(
            left: dot / 2 - 0.5,
            top: dot,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: AppColors.line),
          ),
        body,
        Positioned(
          left: 0,
          top: 0,
          child: _Dot(kind: kind, isNewest: isNewest),
        ),
      ],
    );

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: semanticsLabel(
        e,
        title: title,
        ago: ago,
        percent: percent,
        who: who,
        to: to,
      ),
      child: _FadeIn(isFresh: isFresh, child: item),
    );
  }

  /// "Status updated by Arjun Sridhar, 2 hours ago, Open to In progress,
  /// completion 81 percent, remark ...".
  static String semanticsLabel(
    RecordEvent e, {
    required String title,
    required String ago,
    required int? percent,
    required String Function(String) who,
    required List<String> to,
  }) {
    final spoken = ago
        .replaceFirst(' h ago', ' hours ago')
        .replaceFirst(' min ago', ' minutes ago');
    return [
      '$title by ${who(e.by)}',
      if (spoken.isNotEmpty) spoken,
      if (e.fromStatus.isNotEmpty && e.toStatus.isNotEmpty)
        '${e.fromStatus} ${TicketsTexts.arrowWord} ${e.toStatus}'
      else if (e.toStatus.isNotEmpty)
        e.toStatus,
      if (e.op == 'sent' && to.length > 1) to.join(', '),
      if (percent != null) 'completion $percent percent',
      if (e.hours.isNotEmpty) 'hours ${e.hours}',
      if (e.reason.isNotEmpty) '${TicketsTexts.reasonLabel} ${e.reason}',
      if (e.remarks.isNotEmpty) 'remark ${e.remarks}',
      for (final c in e.changes) '${c.field} ${c.from} to ${c.to}',
    ].join(', ');
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.kind, required this.isNewest});

  final HistoryKind kind;
  final bool isNewest;

  @override
  Widget build(BuildContext context) {
    final tone = kind.tone;
    final icon = kind.icon;
    return Container(
      width: TicketHistoryItem.dot,
      height: TicketHistoryItem.dot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isNewest ? tone.tintStrong : tone.tint,
        border: isNewest
            ? Border.all(color: tone.solid.withValues(alpha: 0.45), width: 1.5)
            : null,
      ),
      alignment: Alignment.center,
      child: icon == null
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.solid,
              ),
            )
          : Icon(icon, size: 16, color: isNewest ? tone.strong : tone.solid),
    );
  }
}

/// A short fade when an event arrives live; it only plays when the item is
/// created fresh.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.isFresh, required this.child});

  final bool isFresh;
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.reduced,
    value: widget.isFresh ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.isFresh) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _controller, child: widget.child);
}
