import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/attachment_tag.dart';
import '../../../core/widgets/app_button.dart';
import '../conversation_controller.dart';

/// What an `[ATTACHMENT]` message shows: a rounded picture that opens full
/// screen, or (for anything else) a file row that downloads and opens.
class AttachmentView extends StatelessWidget {
  const AttachmentView({
    super.key,
    required this.tag,
    required this.controller,
  });

  final AttachmentTag tag;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) => tag.isImage
      ? _Picture(tag: tag, controller: controller)
      : _FileRow(tag: tag, controller: controller);
}

class _Picture extends StatelessWidget {
  const _Picture({required this.tag, required this.controller});

  final AttachmentTag tag;
  final ConversationController controller;

  static const _decodeWidth = 2 * AppSpacing.attachmentWidth;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final retries = c.imageRetries[tag.url] ?? 0;
      final provider = c.imageOf(tag);
      final isLoading = c.isImageLoading(tag);
      final error = _PictureError(
        message: c.imageProblem(tag),
        onRetry: () => c.retryImage(tag),
      );
      return GestureDetector(
        onTap: provider == null
            ? null
            : () {
                c.viewedImage(tag);
                AttachmentViewer.show(context, provider);
              },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            width: AppSpacing.attachmentWidth,
            height: AppSpacing.attachmentHeight,
            child: ColoredBox(
              color: AppColors.sage,
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.muted,
                      ),
                    )
                  : provider == null
                  ? error
                  : Image(
                      key: ValueKey('${tag.url}#$retries'),
                      image: ResizeImage(provider, width: _decodeWidth.toInt()),
                      fit: BoxFit.cover,
                      frameBuilder: (context, child, frame, isSync) =>
                          AnimatedOpacity(
                            opacity: isSync || frame != null ? 1 : 0,
                            duration: AppDurations.base,
                            curve: AppCurves.out,
                            child: child,
                          ),
                      errorBuilder: (context, _, _) => error,
                    ),
            ),
          ),
        ),
      );
    });
  }
}

class _PictureError extends StatelessWidget {
  const _PictureError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.broken_image_outlined, size: 28, color: AppColors.muted),
      const SizedBox(height: AppSpacing.xxs),
      Text(message, textAlign: TextAlign.center, style: AppText.caption),
      AppButton.text(label: 'Retry', onPressed: onRetry),
    ],
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.tag, required this.controller});

  final AttachmentTag tag;
  final ConversationController controller;

  static IconData _iconFor(String name) {
    final dot = name.lastIndexOf('.');
    return switch (dot < 0 ? '' : name.substring(dot + 1).toLowerCase()) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'docx' => Icons.description_outlined,
      'xlsx' => Icons.table_chart_outlined,
      'pptx' => Icons.slideshow_outlined,
      'txt' => Icons.article_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final name = tag.name.isEmpty ? 'File' : tag.name;
    return Obx(() {
      final download = c.downloads[tag.url];
      final isFailed = download?.isFailed.value ?? false;
      final isBusy = download != null && !isFailed;
      final subtitle = isFailed
          ? '${download?.error.value ?? ''} Tap to retry'
          : isBusy
          ? 'Downloading…'
          : tag.size.isEmpty
          ? 'Tap to open'
          : '${tag.size} · Tap to open';
      return Semantics(
        button: true,
        label: isBusy ? '$name, downloading' : '$name, tap to open',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isBusy ? null : () => c.openFile(tag),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.attachmentWidth,
              minHeight: AppSpacing.minTapTarget,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: AppSpacing.minTapTarget,
                  height: AppSpacing.minTapTarget,
                  child: isBusy
                      ? _Ring(
                          progress: download.progress,
                          onCancel: () => c.cancelDownload(tag),
                        )
                      : Icon(
                          isFailed ? Icons.refresh : _iconFor(tag.name),
                          size: AppSpacing.fileIcon,
                          color: isFailed
                              ? AppColors.error
                              : AppColors.cardMuted,
                        ),
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.message,
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: isFailed
                            ? AppText.caption.copyWith(color: AppColors.error)
                            : AppText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// The download ring with a cancel cross in it.
class _Ring extends StatelessWidget {
  const _Ring({required this.progress, required this.onCancel});

  final RxDouble progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Cancel download',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCancel,
      child: Center(
        child: SizedBox(
          width: AppSpacing.fileIcon,
          height: AppSpacing.fileIcon,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Obx(
                () => CircularProgressIndicator(
                  value: progress.value > 0 ? progress.value : null,
                  strokeWidth: 2,
                  color: AppColors.accent,
                  backgroundColor: AppColors.line,
                ),
              ),
              const Icon(Icons.close, size: 14, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A picture on its own full-screen page: pinch to zoom, close at the top.
class AttachmentViewer extends StatelessWidget {
  const AttachmentViewer({super.key, required this.provider});

  final ImageProvider provider;

  static Future<void> show(BuildContext context, ImageProvider provider) =>
      showGeneralDialog<void>(
        context: context,
        barrierLabel: 'Photo',
        barrierColor: AppColors.scrim,
        transitionDuration: AppDurations.base,
        pageBuilder: (context, _, _) => AttachmentViewer(provider: provider),
        transitionBuilder: (context, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: AppCurves.out),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.scrim,
    child: Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image(
                image: provider,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      ),
                errorBuilder: (context, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: AppColors.background,
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Semantics(
              button: true,
              label: 'Close',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox(
                  width: AppSpacing.iconButton,
                  height: AppSpacing.iconButton,
                  child: Icon(Icons.close, color: AppColors.background),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
