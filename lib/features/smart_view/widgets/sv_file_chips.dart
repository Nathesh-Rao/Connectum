import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import '../../../data/smart_view/sv_file.dart';

/// Opens the viewer on [files] at [index].
typedef SvFileOpener = void Function(List<SvFile> files, int index);

IconData svFileIcon(SvFileKind kind) => switch (kind) {
  SvFileKind.image => Icons.image_outlined,
  SvFileKind.pdf => Icons.picture_as_pdf_outlined,
  SvFileKind.video => Icons.movie_outlined,
  SvFileKind.audio => Icons.audiotrack_outlined,
  SvFileKind.text => Icons.description_outlined,
  SvFileKind.office => Icons.article_outlined,
  SvFileKind.archive => Icons.folder_zip_outlined,
  SvFileKind.other => Icons.insert_drive_file_outlined,
};

/// One file as a compact chip: a tinted type icon, the name on one line with
/// the middle cut out (extension kept) and the size muted. The hit area is at
/// least 44 dp tall whatever the chip looks like.
class SvFileChip extends StatelessWidget {
  const SvFileChip({super.key, required this.file, this.onTap});

  final SvFile file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: file.semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSv.fileMinHit,
            maxWidth: AppSv.fileChipMaxWidth,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: _Box(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AppSv.fileChipHeight,
                    height: AppSv.fileChipHeight,
                    decoration: BoxDecoration(
                      color: file.kind.palette.background,
                      borderRadius: BorderRadius.circular(AppSv.fileChipRadius),
                    ),
                    child: Icon(
                      svFileIcon(file.kind),
                      size: AppSv.fileChipIcon,
                      color: file.kind.palette.foreground,
                    ),
                  ),
                  const SizedBox(width: AppSv.fileChipGap),
                  Flexible(child: _NameMeta(file: file)),
                  const SizedBox(width: AppSv.fileChipGap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The name, cut with an ellipsis, then "TYPE · size", which is measured first
/// so it always stays readable. With [isFill] the type and size sit at the
/// right edge.
class _NameMeta extends StatelessWidget {
  const _NameMeta({required this.file, this.isFill = false});

  final SvFile file;
  final bool isFill;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: file.metaText, style: AppSv.fileChipSize),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final metaWidth = math.min(
          painter.width.ceilToDouble() + 1,
          box.maxWidth,
        );
        painter.dispose();
        final hasName = box.maxWidth - metaWidth - AppSv.fileChipGap > 0;
        final meta = SizedBox(
          width: metaWidth,
          child: Text(
            file.metaText,
            style: AppSv.fileChipSize,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        );
        final name = Text(
          file.name,
          style: AppSv.fileChipName,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );
        return Row(
          mainAxisSize: isFill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (hasName) ...[
              isFill ? Expanded(child: name) : Flexible(child: name),
              const SizedBox(width: AppSv.fileChipGap),
            ],
            meta,
          ],
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceSubtle,
      borderRadius: BorderRadius.circular(AppSv.fileChipRadius),
      border: Border.all(color: AppSv.cardBorder),
    ),
    child: child,
  );
}

/// "+N" / "+N more": the rest of the files; opens the viewer there.
class SvFileMoreChip extends StatelessWidget {
  const SvFileMoreChip({
    super.key,
    required this.count,
    required this.onTap,
    this.hasWord = true,
  });

  final int count;
  final VoidCallback? onTap;
  final bool hasWord;

  @override
  Widget build(BuildContext context) {
    final label = hasWord ? '+$count more' : '+$count';
    return Semantics(
      button: onTap != null,
      label: '$count more files',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSv.fileMinHit,
            minWidth: AppSv.fileMinHit,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Container(
              height: AppSv.fileChipHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.violetTint,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: AppSv.fileChipName.copyWith(
                      color: AppColors.violetStrong,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One file as a full-width tile: the tinted type icon, the name with the
/// middle cut out (extension kept) and the size on the right. Every tile of a
/// list has the same width and height; the hit area is 44 dp tall.
class SvFileTile extends StatelessWidget {
  const SvFileTile({super.key, required this.file, this.onTap});

  final SvFile file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: file.semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: AppSv.fileMinHit,
          width: double.infinity,
          child: Center(
            child: Container(
              height: AppSv.fileTileHeight,
              padding: const EdgeInsets.only(right: AppSv.fileChipGap),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(AppSv.fileChipRadius),
                border: Border.all(color: AppSv.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: AppSv.fileTileHeight - 2,
                    height: AppSv.fileTileHeight - 2,
                    decoration: BoxDecoration(
                      color: file.kind.palette.background,
                      borderRadius: BorderRadius.circular(AppSv.fileChipRadius),
                    ),
                    child: Icon(
                      svFileIcon(file.kind),
                      size: AppSv.fileChipIcon,
                      color: file.kind.palette.foreground,
                    ),
                  ),
                  const SizedBox(width: AppSv.fileChipGap),
                  Expanded(child: _NameMeta(file: file, isFill: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Show less" pill, the twin of [SvFileMoreChip].
class SvFileLessChip extends StatelessWidget {
  const SvFileLessChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Show fewer files',
    excludeSemantics: true,
    onTap: onTap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSv.fileMinHit),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Container(
            height: AppSv.fileChipHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.violetTint,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Show less',
                  maxLines: 1,
                  softWrap: false,
                  style: AppSv.fileChipName.copyWith(
                    color: AppColors.violetStrong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A record's files in the value half of a card row or the record details:
/// full-width tiles. With [onToggle] the first [AppSv.fileChipsMax] show and
/// a "+N more" pill opens the rest in place (then "Show less"); without it
/// (the record details) every file shows.
class SvFileChips extends StatelessWidget {
  const SvFileChips({
    super.key,
    required this.files,
    this.onOpen,
    this.isExpanded = false,
    this.onToggle,
  });

  final List<SvFile> files;
  final SvFileOpener? onOpen;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    final isFolded =
        onToggle != null && !isExpanded && files.length > AppSv.fileChipsMax;
    final count = isFolded ? AppSv.fileChipsMax : files.length;
    final rest = files.length - count;
    final hasLess =
        onToggle != null && isExpanded && files.length > AppSv.fileChipsMax;
    return AnimatedSize(
      duration: AppDurations.smartControls,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            SvFileTile(
              key: ValueKey('sv-file-tile-${files[i].id}'),
              file: files[i],
              onTap: open == null ? null : () => open(files, i),
            ),
          if (isFolded) SvFileMoreChip(count: rest, onTap: onToggle),
          if (hasLess) SvFileLessChip(onTap: onToggle!),
        ],
      ),
    );
  }
}

/// A table cell: the first file's chip and a "+N" badge, on one line.
class SvFileTableCell extends StatelessWidget {
  const SvFileTableCell({super.key, required this.files, this.onOpen});

  final List<SvFile> files;
  final SvFileOpener? onOpen;

  @override
  Widget build(BuildContext context) {
    final open = onOpen;
    void tap() => open?.call(files, 0);
    return Row(
      children: [
        Flexible(
          child: SvFileChip(
            file: files.first,
            onTap: open == null ? null : tap,
          ),
        ),
        if (files.length > 1) ...[
          const SizedBox(width: AppSv.fileChipGap),
          SvFileMoreChip(
            count: files.length - 1,
            hasWord: false,
            onTap: open == null ? null : tap,
          ),
        ],
      ],
    );
  }
}
