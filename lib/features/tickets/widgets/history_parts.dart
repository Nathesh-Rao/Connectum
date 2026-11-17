import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../tickets_texts.dart';
import 'ticket_status_pill.dart';

/// The small arrow between "from" and "to" in the history, lightly tinted.
class HistoryArrow extends StatelessWidget {
  const HistoryArrow({super.key});

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.arrow_forward, size: 12, color: AppColors.primaryBright);
}

/// A tiny progress arc: [value] 0 to 1.
class HistoryArc extends StatelessWidget {
  const HistoryArc({super.key, required this.value, required this.color});

  final double value;
  final Color color;

  static const size = 13.0;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(size, size),
    painter: _ArcPainter(value.clamp(0.0, 1.0), color),
  );
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.value, this.color);

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    final box = rect.deflate(1);
    canvas.drawArc(
      box,
      0,
      math.pi * 2,
      false,
      paint..color = color.withValues(alpha: 0.25),
    );
    if (value <= 0) return;
    canvas.drawArc(
      box,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.value != value || old.color != color;
}

/// "81%" with its arc.
class HistoryCompletion extends StatelessWidget {
  const HistoryCompletion({
    super.key,
    required this.percent,
    this.isMuted = false,
  });

  final int percent;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final tone = isMuted ? AppTones.slate : AppTones.primary;
    return TicketPill(
      label: TicketsTexts.percentValue(percent),
      icon: Icons.circle,
      tone: tone,
      leading: HistoryArc(value: percent / 100, color: tone.solid),
    );
  }
}

/// A status as a pill: the tone of the header pill, a tiny check when final.
class HistoryStatus extends StatelessWidget {
  const HistoryStatus({
    super.key,
    required this.label,
    required this.tone,
    this.isFinal = false,
    this.isMuted = false,
  });

  final String label;
  final AppTone tone;
  final bool isFinal;
  final bool isMuted;

  @override
  Widget build(BuildContext context) => TicketPill(
    label: label,
    icon: isFinal ? Icons.check : Icons.circle,
    tone: isMuted ? AppTones.slate : tone,
    hasDot: !isFinal,
  );
}

/// "from -> to" as two soft chips; several recipients collapse to a name
/// and "+2", and a tap shows them all.
class HistoryPeople extends StatefulWidget {
  const HistoryPeople({super.key, required this.from, required this.to});

  final String from;
  final List<String> to;

  @override
  State<HistoryPeople> createState() => _HistoryPeopleState();
}

class _HistoryPeopleState extends State<HistoryPeople> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final to = widget.to;
    final shown = _isOpen ? to : to.take(1).toList();
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.from.isNotEmpty) ...[
          TicketPill(
            label: widget.from,
            icon: Icons.person_outline,
            tone: AppTones.slate,
          ),
          const HistoryArrow(),
        ],
        for (final name in shown)
          TicketPill(
            label: name,
            icon: Icons.person_outline,
            tone: AppTones.primary,
          ),
        if (to.length > 1 && !_isOpen)
          InkWell(
            borderRadius: AppRadius.pillAll,
            onTap: () => setState(() => _isOpen = true),
            child: TicketPill(
              label: TicketsTexts.plusCount(to.length - 1),
              icon: Icons.expand_more,
              tone: AppTones.slate,
              leading: const Icon(
                Icons.expand_more,
                size: 13,
                color: AppColors.muted,
              ),
            ),
          ),
      ],
    );
  }
}

/// Files of an event as small chips.
class HistoryFiles extends StatelessWidget {
  const HistoryFiles({super.key, required this.names});

  final List<String> names;

  static const maxShown = 3;

  @override
  Widget build(BuildContext context) {
    final extra = names.length - maxShown;
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final name in names.take(maxShown))
          TicketPill(
            label: name,
            icon: Icons.attach_file,
            tone: AppTones.slate,
          ),
        if (extra > 0)
          TicketPill(
            label: TicketsTexts.plusCount(extra),
            icon: Icons.attach_file,
            tone: AppTones.slate,
          ),
      ],
    );
  }
}

/// "field: old -> new" rows, three at most; the rest on a tap.
class HistoryChanges extends StatefulWidget {
  const HistoryChanges({super.key, required this.rows});

  /// (field, old, new).
  final List<(String, String, String)> rows;

  static const maxShown = 3;

  @override
  State<HistoryChanges> createState() => _HistoryChangesState();
}

class _HistoryChangesState extends State<HistoryChanges> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final hidden = rows.length - HistoryChanges.maxShown;
    final shown = _isOpen || hidden <= 0
        ? rows
        : rows.take(HistoryChanges.maxShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (field, from, to) in shown)
          Text.rich(
            TextSpan(
              style: AppText.readable,
              children: [
                TextSpan(
                  text: '$field: ',
                  style: AppText.readableStrong.copyWith(
                    color: AppColors.readOnlyInk,
                  ),
                ),
                TextSpan(text: from),
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    child: HistoryArrow(),
                  ),
                ),
                TextSpan(text: to),
              ],
            ),
          ),
        if (hidden > 0 && !_isOpen)
          InkWell(
            onTap: () => setState(() => _isOpen = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Text(
                TicketsTexts.moreCount(hidden),
                style: AppText.label.copyWith(color: AppColors.primaryBright),
              ),
            ),
          ),
      ],
    );
  }
}

/// A remark, a comment or a reason: a soft block with a thin accent line,
/// three lines at most with "Show more", selectable.
class HistoryQuote extends StatefulWidget {
  const HistoryQuote({super.key, required this.text, this.label = ''});

  final String text;
  final String label;

  static const maxLines = 3;

  @override
  State<HistoryQuote> createState() => _HistoryQuoteState();
}

class _HistoryQuoteState extends State<HistoryQuote> {
  bool _isOpen = false;

  static const _accent = 2.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return ClipRRect(
      borderRadius: AppRadius.controlAll,
      child: ColoredBox(
        color: AppColors.primarySoft,
        child: Stack(
          children: [
            const Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _accent,
              child: ColoredBox(color: AppColors.primaryBorder),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _accent + AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  final painter = TextPainter(
                    text: TextSpan(text: widget.text, style: AppText.body),
                    maxLines: HistoryQuote.maxLines,
                    textDirection: Directionality.of(context),
                    textScaler: scaler,
                  )..layout(maxWidth: box.maxWidth);
                  final isLong = painter.didExceedMaxLines;
                  painter.dispose();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.label.isNotEmpty)
                        Text(widget.label, style: AppText.rowCaption),
                      SelectableText(
                        widget.text,
                        style: AppText.body,
                        maxLines: _isOpen ? null : HistoryQuote.maxLines,
                      ),
                      if (isLong)
                        InkWell(
                          onTap: () => setState(() => _isOpen = !_isOpen),
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xxs),
                            child: Text(
                              _isOpen
                                  ? TicketsTexts.showLess
                                  : TicketsTexts.showMore,
                              style: AppText.label.copyWith(
                                color: AppColors.primaryBright,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
