import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/attachment_tag.dart';
import '../models/document_info.dart';

/// A non-image attachment: a file-type tile, the name, "PDF · 2.4 MB" and one
/// action button (download, progress with cancel, open, retry). Drawn only
/// from what it is given, so the debug page can show every state. Same width
/// and corner as the picture; a white card reads on both bubbles.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.tag,
    required this.state,
    required this.onDownload,
    required this.onOpen,
    required this.onCancel,
    required this.onShare,
    this.progress = 0,
    this.error,
  });

  final AttachmentTag tag;
  final DocumentButtonState state;

  /// 0 to 1; 0 while the length is unknown.
  final double progress;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final info = DocumentInfo.of(tag);
    final isFailed = state == DocumentButtonState.failed;
    final isBusy = state == DocumentButtonState.downloading;
    final detail = isFailed
        ? error ?? "Couldn't download. Tap to retry"
        : isBusy
        ? tag.isEncrypted
              ? 'Decrypting attachment…'
              : 'Downloading…'
        : info.details;
    final label = switch (state) {
      DocumentButtonState.idle => 'Download ${info.name}',
      DocumentButtonState.downloading => 'Downloading ${info.name}, cancel',
      DocumentButtonState.done => 'Open ${info.name}',
      DocumentButtonState.failed => 'Retry download of ${info.name}',
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: switch (state) {
        DocumentButtonState.idle || DocumentButtonState.failed => onDownload,
        DocumentButtonState.downloading => onCancel,
        DocumentButtonState.done => onOpen,
      },
      onLongPress: onShare,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Share or save'): onShare,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: switch (state) {
          DocumentButtonState.idle || DocumentButtonState.failed => onDownload,
          DocumentButtonState.downloading => null,
          DocumentButtonState.done => onOpen,
        },
        onLongPress: onShare,
        child: Container(
          width: AppSpacing.attachmentWidth,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.cardLine),
          ),
          child: Row(
            children: [
              _TypeTile(info: info),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info.shortName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.readableStrong,
                    ),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: isFailed ? AppText.error : AppText.caption,
                    ),
                  ],
                ),
              ),
              _ActionButton(
                state: state,
                progress: progress,
                onCancel: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({required this.info});

  final DocumentInfo info;

  @override
  Widget build(BuildContext context) {
    final palette = info.kind.palette;
    return Container(
      width: AppSpacing.documentTile,
      height: AppSpacing.documentTile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        info.tileLabel,
        maxLines: 1,
        style: AppText.label.copyWith(
          color: palette.foreground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.state,
    required this.progress,
    required this.onCancel,
  });

  final DocumentButtonState state;
  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AppSpacing.documentAction,
        minHeight: AppSpacing.documentAction,
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: AppDurations.fast,
          switchInCurve: AppCurves.out,
          child: KeyedSubtree(
            key: ValueKey(state),
            child: switch (state) {
              DocumentButtonState.idle => const _Round(
                color: AppColors.accent,
                child: Icon(
                  Icons.file_download_outlined,
                  size: 22,
                  color: AppColors.background,
                ),
              ),
              DocumentButtonState.downloading => _Ring(
                progress: progress,
                onCancel: onCancel,
              ),
              DocumentButtonState.done => const _OpenPill(),
              DocumentButtonState.failed => const _Round(
                color: AppColors.background,
                borderColor: AppColors.error,
                child: Icon(Icons.refresh, size: 22, color: AppColors.error),
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.color, required this.child, this.borderColor});

  final Color color;
  final Color? borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: AppSpacing.documentButton,
    height: AppSpacing.documentButton,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: borderColor == null
          ? null
          : Border.all(color: borderColor!, width: 1.5),
    ),
    child: child,
  );
}

class _OpenPill extends StatelessWidget {
  const _OpenPill();

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.accentTint,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: AppColors.tileCurrentBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check, size: 14, color: AppColors.accentInk),
        const SizedBox(width: AppSpacing.xxs),
        Text('Open', style: AppText.label.copyWith(color: AppColors.accentInk)),
      ],
    ),
  );
}

/// The progress ring with the percentage in it, or a cross while the length
/// is unknown. A tap cancels.
class _Ring extends StatelessWidget {
  const _Ring({required this.progress, required this.onCancel});

  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onCancel,
    child: SizedBox(
      width: AppSpacing.documentButton,
      height: AppSpacing.documentButton,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              color: AppColors.accent,
              backgroundColor: AppColors.accentTint,
            ),
          ),
          progress > 0
              ? Text(
                  '${(progress * 100).round()}%',
                  style: AppText.label.copyWith(color: AppColors.accentInk),
                )
              : const Icon(Icons.close, size: 16, color: AppColors.accentInk),
        ],
      ),
    ),
  );
}
