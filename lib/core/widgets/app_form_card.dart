import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/data/models/models.dart';
import 'app_status_pill.dart';

enum AppFormCardState { sent, waiting, failed }

/// A submission as a card in a thread. Sent (mine) is aligned right with an
/// blue strip and, when [onEdit] is given, a pencil; received is aligned
/// left with a dark strip and the sender's name above it when [senderName] is
/// set. It shows the first eight fields in two columns and "+N more" for the
/// rest. [isFresh] makes it enter with a small spring (sent from the right,
/// received from the left).
/// The text styles of a form card. [chat] is the card in a conversation;
/// [workspace] is the larger set of My Work Space.
class AppFormCardText {
  const AppFormCardText({
    required this.sender,
    required this.strip,
    required this.title,
    required this.label,
    required this.value,
    required this.time,
    required this.note,
    required this.more,
  });

  final TextStyle sender;
  final TextStyle strip;
  final TextStyle title;
  final TextStyle label;
  final TextStyle value;
  final TextStyle time;
  final TextStyle note;
  final TextStyle more;

  static final chat = AppFormCardText(
    sender: AppText.label.copyWith(color: AppColors.primaryStrong),
    strip: AppText.label.copyWith(
      color: AppColors.white,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    ),
    title: AppText.bodyStrong.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: -0.2,
    ),
    label: AppText.caption.copyWith(color: AppColors.cardMuted, height: 1.25),
    value: AppText.body.copyWith(fontWeight: FontWeight.w500, height: 1.3),
    time: AppText.caption.copyWith(color: AppColors.cardMuted),
    note: AppText.caption.copyWith(color: AppColors.cardMuted),
    more: AppText.caption.copyWith(color: AppColors.cardMuted),
  );

  static final workspace = AppFormCardText(
    sender: AppText.wsMeta.copyWith(color: AppColors.primaryStrong),
    strip: AppText.wsChip.copyWith(color: AppColors.white),
    title: AppText.wsTitle,
    label: AppText.wsMeta.copyWith(color: AppColors.cardMuted),
    value: AppText.wsSubtitle,
    time: AppText.wsTime.copyWith(color: AppColors.cardMuted),
    note: AppText.wsTime.copyWith(color: AppColors.cardMuted),
    more: AppText.wsMeta.copyWith(color: AppColors.cardMuted),
  );
}

class AppFormCard extends StatefulWidget {
  const AppFormCard({
    super.key,
    required this.data,
    required this.isSent,
    required this.onTap,
    this.onEdit,
    this.onLongPress,
    this.senderName,
    this.isFresh = false,
    this.state = AppFormCardState.sent,
    this.problem,
    this.stripLabel,
    this.note,
    this.isHighlighted = false,
    this.statusMark,
    this.actions,
    this.text,
  });

  static const widthFraction = 0.92;
  static const visibleFields = 8;
  static const _stripHeight = 38.0;
  static const _entryShift = 28.0;

  final FormCardData data;
  final bool isSent;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onLongPress;
  final String? senderName;
  final bool isFresh;

  /// Waiting to be sent, failed, or settled; a failed card shows [problem].
  final AppFormCardState state;
  final String? problem;

  /// Replaces the strip's text (a draft, a record that needs attention) and
  /// adds a quiet line in the footer.
  final String? stripLabel;
  final String? note;

  /// Flashes the card once (it was just changed by an edit).
  final bool isHighlighted;

  /// The sent / delivered / read mark next to the time, for my cards in a
  /// conversation. Without it a waiting card shows a plain clock.
  final Widget? statusMark;

  /// Under the fields, above the time: a ticket's actions, in an
  /// [AppFormCardActionArea]. It may build to nothing.
  final Widget? actions;

  /// Defaults to [AppFormCardText.chat].
  final AppFormCardText? text;

  @override
  State<AppFormCard> createState() => _AppFormCardState();
}

class _AppFormCardState extends State<AppFormCard> {
  bool _isOpen = false;
  bool _isPressed = false;
  bool _isFlashing = false;

  @override
  void initState() {
    super.initState();
    if (widget.isHighlighted) _flash();
  }

  @override
  void didUpdateWidget(AppFormCard old) {
    super.didUpdateWidget(old);
    if (widget.isHighlighted && !old.isHighlighted) _flash();
  }

  void _flash() {
    _isFlashing = true;
    Future<void>.delayed(AppDurations.slow * 2, () {
      if (mounted) setState(() => _isFlashing = false);
    });
  }

  void _setPressed(bool value) {
    if (!mounted || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final t = widget.text ?? AppFormCardText.chat;
    final fields = d.cardEntries;
    final shown = fields.take(AppFormCard.visibleFields).toList();
    final extra = fields.skip(AppFormCard.visibleFields).toList();
    final time = ChatTime.time(d.ts);
    final isWaiting = widget.state == AppFormCardState.waiting;
    final line = _Footer.lineOf(
      problem: widget.state == AppFormCardState.failed ? widget.problem : null,
      note: widget.note,
      isAwaitingApproval: d.isAwaitingApproval,
      style: t.note,
    );
    final stamp = _Stamp(
      time: time,
      isWaiting: isWaiting,
      statusMark: widget.statusMark,
      style: t.time,
    );
    final footer = _Footer(line: line, stamp: stamp);
    Widget card = Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _isPressed ? 0.985 : 1,
          duration: AppDurations.fast,
          curve: AppCurves.out,
          child: AnimatedContainer(
            duration: AppDurations.base,
            curve: AppCurves.out,
            decoration: BoxDecoration(
              color: _isFlashing ? AppColors.primaryTint : AppColors.white,
              borderRadius: AppRadius.cardAll,
              border: Border.all(color: AppColors.cardLine),
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.card - 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Strip(
                    label:
                        widget.stripLabel ??
                        (widget.state == AppFormCardState.waiting
                            ? 'Waiting to send'
                            : d.label),
                    isSent: widget.isSent,
                    onEdit: widget.onEdit,
                    style: t.strip,
                  ),
                  _Title(caption: d.caption, style: t.title),
                  if (fields.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        9,
                        AppSpacing.sm,
                        0,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.cardLine),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Columns(entries: shown, text: t),
                          if (extra.isNotEmpty) ...[
                            AnimatedSize(
                              duration: AppDurations.base,
                              curve: AppCurves.out,
                              alignment: Alignment.topCenter,
                              child: AnimatedOpacity(
                                duration: AppDurations.base,
                                curve: AppCurves.out,
                                opacity: _isOpen ? 1 : 0,
                                child: _isOpen
                                    ? _Columns(entries: extra, text: t)
                                    : const SizedBox(width: double.infinity),
                              ),
                            ),
                            _MoreRow(
                              isOpen: _isOpen,
                              count: extra.length,
                              style: t.more,
                              onTap: () {
                                if (mounted) setState(() => _isOpen = !_isOpen);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (widget.actions != null)
                    AppFormCardScope(
                      timeLabel: time,
                      stamp: stamp,
                      line: line,
                      footer: footer,
                      child: widget.actions!,
                    )
                  else
                    footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.state == AppFormCardState.waiting) {
      card = Opacity(opacity: 0.7, child: card);
    }
    if (widget.isFresh) {
      card = _Entrance(isSent: widget.isSent, child: card);
    }
    return Align(
      alignment: widget.isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: box.maxWidth * AppFormCard.widthFraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.senderName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Text(widget.senderName!, style: t.sender),
                ),
              card,
            ],
          ),
        ),
      ),
    );
  }
}

/// Sets [child] under a card's fields: a hairline inset like the fields',
/// then the child, which spans the card's full width (it adds its own
/// [AppFormCardActionArea.inset] where it needs one).
class AppFormCardActionArea extends StatelessWidget {
  const AppFormCardActionArea({super.key, required this.child});

  final Widget child;

  static const inset = AppSpacing.sm;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(inset, AppSpacing.xxs, inset, 0),
        child: Divider(height: 1, color: AppColors.cardLine),
      ),
      const SizedBox(height: AppSpacing.xs),
      child,
    ],
  );
}

/// What an action area on a card needs to carry the time itself: the bar
/// along the bottom shows [stamp] at its right, so the card has no row of
/// its own under the actions. [footer] is the plain row for when the actions
/// build to nothing.
class AppFormCardScope extends InheritedWidget {
  const AppFormCardScope({
    super.key,
    required this.timeLabel,
    required this.stamp,
    required this.line,
    required this.footer,
    required super.child,
  });

  final String timeLabel;
  final Widget stamp;
  final Widget? line;
  final Widget footer;

  static AppFormCardScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppFormCardScope>();

  @override
  bool updateShouldNotify(AppFormCardScope old) =>
      timeLabel != old.timeLabel ||
      stamp != old.stamp ||
      line != old.line ||
      footer != old.footer;
}

/// The time, with a clock while waiting or the sent / delivered / read mark.
class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.time,
    required this.isWaiting,
    required this.statusMark,
    required this.style,
  });

  final String time;
  final bool isWaiting;
  final Widget? statusMark;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isWaiting && statusMark == null) ...[
          const Icon(Icons.schedule, size: 12, color: AppColors.cardMuted),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Text(time, style: style),
        if (statusMark != null) ...[
          const SizedBox(width: AppSpacing.xxs),
          statusMark!,
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.line, required this.stamp});

  final Widget? line;
  final Widget stamp;

  static Widget? lineOf({
    required String? problem,
    required String? note,
    required bool isAwaitingApproval,
    required TextStyle style,
  }) => problem != null
      ? Text(problem, style: style.copyWith(color: AppColors.error))
      : note != null
      ? Text(note, style: style)
      : isAwaitingApproval
      ? Text('Waiting for approval', style: style)
      : null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xxs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: line ?? const SizedBox.shrink()),
          const SizedBox(width: AppSpacing.xs),
          stamp,
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.label,
    required this.isSent,
    required this.onEdit,
    required this.style,
  });

  final String label;
  final bool isSent;
  final VoidCallback? onEdit;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppFormCard._stripHeight,
      padding: const EdgeInsets.only(left: AppSpacing.sm, right: 6),
      color: isSent ? AppColors.primary : AppColors.ink,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (onEdit != null)
            Semantics(
              button: true,
              label: 'Edit submission',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onEdit,
                child: SizedBox(
                  width: AppFormCard._stripHeight,
                  height: AppFormCard._stripHeight,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.2),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppRadius.segment),
                        ),
                        border: Border.all(
                          color: AppColors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.caption, required this.style});

  final String caption;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 10, AppSpacing.sm, 0),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.all(Radius.circular(9)),
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 16,
              color: AppColors.primaryBright,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$caption submitted',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two columns, the left one filled first, with a hairline between them.
class _Columns extends StatelessWidget {
  const _Columns({required this.entries, required this.text});

  final List<FormEntry> entries;
  final AppFormCardText text;

  @override
  Widget build(BuildContext context) {
    final split = (entries.length + 1) ~/ 2;
    final left = entries.sublist(0, split);
    final right = entries.sublist(split);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _Column(entries: left, text: text),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(left: 10),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.cardLine)),
              ),
              child: _Column(entries: right, text: text),
            ),
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.entries, required this.text});

  final List<FormEntry> entries;
  final AppFormCardText text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          _Field(
            entry: entries[i],
            isLast: i == entries.length - 1,
            text: text,
          ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.entry, required this.isLast, required this.text});

  final FormEntry entry;
  final bool isLast;
  final AppFormCardText text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.cardLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.caption, style: text.label),
          const SizedBox(height: 3),
          switch (entry.kind) {
            FormEntryKind.yes || FormEntryKind.no => AppStatusPill(
              isYes: entry.kind == FormEntryKind.yes,
            ),
            FormEntryKind.location => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.place_outlined,
                    size: 14,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    entry.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.value,
                  ),
                ),
              ],
            ),
            FormEntryKind.text => Text(
              entry.text,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: text.value,
            ),
          },
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.isOpen,
    required this.count,
    required this.onTap,
    required this.style,
  });

  final bool isOpen;
  final int count;
  final VoidCallback onTap;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isOpen ? 'Show less' : '+$count more', style: style),
            const SizedBox(width: AppSpacing.xxs),
            AnimatedRotation(
              turns: isOpen ? 0.5 : 0,
              duration: AppDurations.fast,
              curve: AppCurves.out,
              child: const Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: AppColors.cardMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.isSent, required this.child});

  final bool isSent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppDurations.slow,
      curve: AppCurves.sheet,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(
            (isSent ? 1 : -1) * AppFormCard._entryShift * (1 - t),
            0,
          ),
          child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
        ),
      ),
    );
  }
}
