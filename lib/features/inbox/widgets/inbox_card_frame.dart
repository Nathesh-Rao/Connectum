import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../smart_view/widgets/sv_file_chips.dart';
import '../models/inbox_card_rows.dart';
import '../models/inbox_record_tone.dart';
import 'inbox_file_chip.dart';

/// Where a card stands: the colour and the icon of its status circle.
enum InboxCardStatus {
  completed(Icons.check_rounded),
  rejected(Icons.close_rounded),
  waiting(Icons.hourglass_top_rounded),
  pending(Icons.priority_high_rounded),
  assigned(Icons.person_rounded),
  closed(Icons.remove_rounded);

  const InboxCardStatus(this.icon);

  final IconData icon;

  AppTone get tone => switch (this) {
    InboxCardStatus.completed => AppTones.green,
    InboxCardStatus.rejected => AppTones.red,
    InboxCardStatus.waiting => AppTones.violet,
    InboxCardStatus.pending => AppTones.yellow,
    InboxCardStatus.assigned => AppTones.blue,
    InboxCardStatus.closed => AppTones.slate,
  };

  static InboxCardStatus of(InboxState s) => switch (s) {
    InboxState.completed => InboxCardStatus.completed,
    InboxState.rejected => InboxCardStatus.rejected,
    InboxState.waiting => InboxCardStatus.waiting,
    InboxState.pending => InboxCardStatus.pending,
    InboxState.assigned => InboxCardStatus.assigned,
  };
}

/// The card of the Inbox, for a record and for an approval: a clean surface
/// with a hairline border and a faint wash of the state's colour in the top
/// right corner. A header (the face; the title, the person with a small icon and
/// `#id`, date and time; the priority dot and the status circle, then the menu
/// when there is one, else the circle sits at the right edge), rows with an
/// icon, a label and a value (files as one chip), "Show more", the status as
/// a strip across the bottom, and a footer. No inner scrolling, no coloured
/// band.
class InboxCardFrame extends StatelessWidget {
  const InboxCardFrame({
    super.key,
    required this.leading,
    required this.title,
    required this.idText,
    required this.status,
    required this.statusLabel,
    required this.isExpanded,
    required this.onToggle,
    this.ts = 0,
    this.name = '',
    this.strip = '',
    this.priorityTone,
    this.priorityLabel = '',
    this.menu,
    this.rows = const [],
    this.footer,
    this.onTap,
    this.onOpenFiles,
    this.isFilesOpen,
    this.onToggleFiles,
  });

  /// Rows shown before "Show more".
  static const maxRows = 4;

  final Widget leading;
  final String title;

  /// The person's name, between the title and the meta line.
  final String name;

  /// `#573`.
  final String idText;

  /// Epoch ms of the record; 0 hides the date and the time.
  final int ts;
  final InboxCardStatus status;

  /// What the status circle says to a screen reader ("Pending", "Approved").
  final String statusLabel;

  /// The words of the status as a strip across the bottom, above the footer;
  /// none when empty.
  final String strip;

  final AppTone? priorityTone;
  final String priorityLabel;

  /// The three dots; null when the person has no action: the status circle
  /// then sits at the far right edge.
  final Widget? menu;
  final List<InboxCardRow> rows;
  final Widget? footer;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onTap;

  /// Opens the files of a row; null leaves the file chip plain.
  final SvFileOpener? onOpenFiles;

  /// Whether the chips of the file row [name] are all shown, and the toggle
  /// of that ("+N more" / "Show less").
  final bool Function(String name)? isFilesOpen;
  final void Function(String name)? onToggleFiles;

  @override
  Widget build(BuildContext context) {
    final tone = status.tone;
    final hasMore = rows.length > maxRows;
    final shown = hasMore && !isExpanded ? rows.take(maxRows).toList() : rows;
    return Semantics(
      container: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: const BorderSide(color: AppColors.cardLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned.fill(child: InboxCardWash(tone: tone)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.sm,
                      AppSpacing.sm,
                      menu == null ? AppSpacing.sm : AppSpacing.xs,
                      0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        leading,
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: _Header(
                            title: title,
                            name: name,
                            idText: idText,
                            ts: ts,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (priorityTone != null)
                              Semantics(
                                label: priorityLabel,
                                child: Tooltip(
                                  message: priorityLabel,
                                  child: Container(
                                    width: AppSpacing.inboxPriorityDot,
                                    height: AppSpacing.inboxPriorityDot,
                                    margin: const EdgeInsetsDirectional.only(
                                      end: AppSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: priorityTone!.solid,
                                    ),
                                  ),
                                ),
                              ),
                            _StatusCircle(status: status, label: statusLabel),
                            ?menu,
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (rows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const Divider(height: 1, color: AppColors.cardLine),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: AppAnimatedSize(
                        duration: AppDurations.sheetResize,
                        curve: AppCurves.out,
                        alignment: Alignment.topCenter,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final r in shown)
                              _RowLine(
                                row: r,
                                onOpenFiles: onOpenFiles,
                                isFilesOpen: isFilesOpen,
                                onToggleFiles: onToggleFiles,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Semantics(
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onToggle,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.xs,
                                ),
                                child: Text(
                                  isExpanded
                                      ? 'Show less'
                                      : 'Show more (${rows.length - maxRows})',
                                  style: AppText.readableStrong.copyWith(
                                    color: AppColors.primaryStrong,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ] else
                    const SizedBox(height: AppSpacing.xs),
                  if (strip.isNotEmpty)
                    InboxStatusStrip(status: status, text: strip),
                  if (footer != null) ...[
                    if (strip.isEmpty)
                      const Divider(height: 1, color: AppColors.cardLine),
                    footer!,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title, the person and `#id`, date and time.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.name,
    required this.idText,
    required this.ts,
  });

  final String title;
  final String name;
  final String idText;
  final int ts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.inboxTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Row(
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: AppSpacing.inboxMetaIcon + 2,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    name,
                    style: AppText.inboxName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                idText,
                style: AppText.inboxMeta.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              if (ts > 0) ...[
                _MetaItem(
                  icon: Icons.calendar_today_outlined,
                  text: ChatTime.date(ts),
                  label: 'Date',
                ),
                _MetaItem(
                  icon: Icons.schedule_rounded,
                  text: ChatTime.time(ts),
                  label: 'Time',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.text,
    required this.label,
  });

  final IconData icon;
  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $text',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSpacing.inboxMetaIcon, color: AppColors.muted),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(child: Text(text, style: AppText.inboxMeta)),
        ],
      ),
    );
  }
}

/// A faint wash behind a corner of the card: two soft overlapping circles
/// (4 to 7 percent of [color], else the tone's solid), clipped by the card's
/// rounded shape. In the top right corner, or [isMirrored] in the top left.
/// One cheap painter in its own layer, painted once.
class InboxCardWash extends StatelessWidget {
  const InboxCardWash({
    super.key,
    this.tone,
    this.color,
    this.isMirrored = false,
    this.strength = 1,
  }) : assert(tone != null || color != null);

  final AppTone? tone;

  /// Overrides the tone's solid.
  final Color? color;
  final bool isMirrored;

  /// Multiplies the alpha of both circles.
  final double strength;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _WashPainter(
            color ?? tone!.solid,
            isMirrored: isMirrored,
            strength: strength,
          ),
        ),
      ),
    ),
  );
}

/// The top left wash of a card, from the person's picture: its vibrant colour
/// read off the first frame (cached per address) and faded in; the initials
/// colour when there is no picture or no colour could be read. The alpha is
/// capped so the title and the name stay readable.
class InboxAvatarWash extends StatelessWidget {
  const InboxAvatarWash({super.key, required this.picture});

  /// Twice the corner wash of the state: still soft behind the text.
  static const strength = 2.0;

  final String? picture;

  @override
  Widget build(BuildContext context) {
    Widget wash(Color? c) => InboxCardWash(
      key: ValueKey('inbox-avatar-wash-${c != null}'),
      color: c ?? AppColors.avatarText,
      isMirrored: true,
      strength: strength,
    );
    if (AvatarTint.isKnown(picture)) return wash(AvatarTint.peek(picture));
    return FutureBuilder<Color?>(
      future: AvatarTint.of(picture),
      builder: (context, snapshot) => AnimatedOpacity(
        opacity: snapshot.connectionState == ConnectionState.done ? 1 : 0,
        duration: AppDurations.slow,
        curve: AppCurves.out,
        child: wash(snapshot.data),
      ),
    );
  }
}

class _WashPainter extends CustomPainter {
  const _WashPainter(
    this.color, {
    required this.isMirrored,
    required this.strength,
  });

  final Color color;
  final bool isMirrored;
  final double strength;

  static const _big = 84.0;
  static const _small = 46.0;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double fromEdge) => isMirrored ? fromEdge : size.width - fromEdge;
    canvas.drawCircle(
      Offset(x(-8), -8),
      _big,
      Paint()..color = color.withValues(alpha: 0.05 * strength),
    );
    canvas.drawCircle(
      Offset(x(34), 14),
      _small,
      Paint()..color = color.withValues(alpha: 0.06 * strength),
    );
  }

  @override
  bool shouldRepaint(_WashPainter old) =>
      old.color != color ||
      old.isMirrored != isMirrored ||
      old.strength != strength;
}

/// The status as a full-width tinted strip, on a card and on the record
/// screen.
class InboxStatusStrip extends StatelessWidget {
  const InboxStatusStrip({super.key, required this.status, required this.text});

  final InboxCardStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tone = status.tone;
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('inbox-status-strip'),
        constraints: const BoxConstraints(
          minHeight: AppSpacing.inboxStripHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        color: tone.tint,
        child: Row(
          children: [
            Icon(
              status.icon,
              size: AppSpacing.inboxMetaIcon + 2,
              color: tone.strong,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: AppText.readableStrong.copyWith(color: tone.strong),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCircle extends StatelessWidget {
  const _StatusCircle({required this.status, required this.label});

  final InboxCardStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('inbox-status-circle'),
          width: AppSpacing.inboxStatusCircle,
          height: AppSpacing.inboxStatusCircle,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: status.tone.solid,
          ),
          child: Icon(
            status.icon,
            size: AppSpacing.inboxStatusCircle * 0.68,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}

class _RowLine extends StatelessWidget {
  const _RowLine({
    required this.row,
    this.onOpenFiles,
    this.isFilesOpen,
    this.onToggleFiles,
  });

  final InboxCardRow row;
  final SvFileOpener? onOpenFiles;
  final bool Function(String name)? isFilesOpen;
  final void Function(String name)? onToggleFiles;

  @override
  Widget build(BuildContext context) {
    final tone = row.kind.tone;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs - 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              key: ValueKey('inbox-row-icon-${row.kind.name}'),
              width: AppSpacing.inboxFieldIcon,
              height: AppSpacing.inboxFieldIcon,
              decoration: BoxDecoration(
                color: tone.tint,
                borderRadius: AppRadius.controlAll,
              ),
              child: Icon(row.kind.icon, size: 16, color: tone.strong),
            ),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: AppText.inboxLabel),
                const SizedBox(height: 2),
                if (row.hasFiles && row.hasFileInfo)
                  SvFileChips(
                    files: row.files,
                    onOpen: onOpenFiles,
                    isExpanded: isFilesOpen?.call(row.name) ?? false,
                    onToggle: onToggleFiles == null
                        ? null
                        : () => onToggleFiles!(row.name),
                  )
                else if (row.hasFiles)
                  InboxFileChip(
                    files: row.files,
                    onOpen: onOpenFiles == null
                        ? null
                        : (files) => onOpenFiles!(files, 0),
                  )
                else
                  Text(row.value, style: AppText.inboxValue),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
