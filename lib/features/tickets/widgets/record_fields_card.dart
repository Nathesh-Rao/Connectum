import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/smart_view/smart_view.dart';
import '../../inbox/models/inbox_card_rows.dart';
import '../../inbox/models/inbox_field_kind.dart';
import '../../inbox/widgets/inbox_file_chip.dart';
import '../tickets_texts.dart';

/// One line of the record's fields card: an icon, a label and a value.
class RecordFieldLine {
  const RecordFieldLine({
    required this.icon,
    required this.tone,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final AppTone tone;
  final String label;
  final Widget child;
}

/// The answers of a record as one grouped card: each line with its type icon,
/// label and value, a hairline between them. People show a face and a name,
/// files the Smart View file chips (a lone "n files" chip when the server sent
/// no details).
class RecordFieldsCard extends StatelessWidget {
  const RecordFieldsCard({
    super.key,
    required this.rows,
    required this.nameOf,
    required this.pictureOf,
    this.onOpenFiles,
    this.isFilesOpen,
    this.onToggleFiles,
    this.leading = const [],
  });

  /// Lines drawn first (who holds it, how far it is).
  final List<RecordFieldLine> leading;
  final List<InboxCardRow> rows;
  final String Function(String user) nameOf;
  final String? Function(String user) pictureOf;
  final SvFileOpener? onOpenFiles;

  /// Whether the chips of the file line [name] are all shown, and its toggle.
  final bool Function(String name)? isFilesOpen;
  final void Function(String name)? onToggleFiles;

  @override
  Widget build(BuildContext context) {
    final lines = [
      ...leading,
      for (final r in rows)
        RecordFieldLine(
          icon: r.kind.icon,
          tone: r.kind.tone,
          label: r.name,
          child: _value(r),
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      key: const ValueKey('record-fields-card'),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.cardLine),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Column(
          children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.cardLine),
              _Line(line: lines[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _value(InboxCardRow r) {
    if (r.hasFiles) {
      if (!r.hasFileInfo) {
        final open = onOpenFiles;
        return InboxFileChip(
          files: r.files,
          onOpen: open == null ? null : (files) => open(files, 0),
        );
      }
      return SvFileChips(
        files: r.files,
        onOpen: onOpenFiles,
        isExpanded: isFilesOpen?.call(r.name) ?? false,
        onToggle: onToggleFiles == null ? null : () => onToggleFiles!(r.name),
      );
    }
    if (r.kind == InboxFieldKind.person) {
      return RecordPeople(
        users: _peopleOf(r.value),
        nameOf: nameOf,
        pictureOf: pictureOf,
      );
    }
    return Text(r.value, style: AppText.inboxValue);
  }

  static List<String> _peopleOf(String value) => [
    for (final p in value.split(','))
      if (p.replaceFirst('@', '').trim().isNotEmpty)
        p.replaceFirst('@', '').trim(),
  ];
}

class _Line extends StatelessWidget {
  const _Line({required this.line});

  final RecordFieldLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: AppSpacing.inboxFieldIcon,
              height: AppSpacing.inboxFieldIcon,
              decoration: BoxDecoration(
                color: line.tone.tint,
                borderRadius: AppRadius.controlAll,
              ),
              child: Icon(line.icon, size: 16, color: line.tone.strong),
            ),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.label, style: AppText.inboxLabel),
                const SizedBox(height: 2),
                line.child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// People as a face and a display name each.
class RecordPeople extends StatelessWidget {
  const RecordPeople({
    super.key,
    required this.users,
    required this.nameOf,
    required this.pictureOf,
  });

  final List<String> users;
  final String Function(String user) nameOf;
  final String? Function(String user) pictureOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final u in users)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAvatar(
                name: nameOf(u),
                size: AppSpacing.chipAvatar,
                picture: pictureOf(u),
              ),
              const SizedBox(width: AppSpacing.xxs + 2),
              Flexible(child: Text(nameOf(u), style: AppText.inboxValue)),
            ],
          ),
      ],
    );
  }
}

/// How far a record is, as a line of the card.
class RecordCompletion extends StatelessWidget {
  const RecordCompletion({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: AppProgressBar(value: percent / 100)),
      const SizedBox(width: AppSpacing.xs),
      Text(TicketsTexts.percentValue(percent), style: AppText.readableStrong),
    ],
  );
}
