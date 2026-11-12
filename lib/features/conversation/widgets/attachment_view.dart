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
import '../models/document_info.dart';
import 'document_card.dart';
import '../../../core/widgets/app_spinner.dart';

/// What an `[ATTACHMENT]` message shows: a rounded picture that opens full
/// screen, or (for anything else) a document card that downloads and opens.
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
      : _Document(tag: tag, controller: controller);
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
              color: AppColors.fill,
              child: isLoading
                  ? const Center(
                      child: AppSpinner(
                        size: AppSpinnerSize.lg,
                        isStandalone: true,
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

class _Document extends StatelessWidget {
  const _Document({required this.tag, required this.controller});

  final AttachmentTag tag;
  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final download = c.downloads[tag.url];
      return DocumentCard(
        tag: tag,
        state: DocumentButtonState.of(
          isSaved: c.isSaved(tag),
          download: download,
        ),
        progress: download?.progress.value ?? 0,
        error: download?.error.value,
        onDownload: () => c.downloadFile(tag),
        onOpen: () => c.openFile(tag),
        onCancel: () => c.cancelDownload(tag),
        onShare: () => c.shareFile(tag),
      );
    });
  }
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
                        child: AppSpinner(
                          size: AppSpinnerSize.lg,
                          isStandalone: true,
                        ),
                      ),
                errorBuilder: (context, _, _) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: AppColors.white,
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
                  child: Icon(Icons.close, color: AppColors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
