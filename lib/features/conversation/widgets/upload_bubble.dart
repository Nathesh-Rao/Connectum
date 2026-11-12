import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/attachment_tag.dart';
import '../../../core/widgets/app_progress_bar.dart';

import '../models/pending_upload.dart';

/// My photo or document while it uploads: the picture (or the file's name)
/// with a thin progress bar over it and a cancel; on failure the reason with Retry and Cancel.
class UploadBubble extends StatelessWidget {
  const UploadBubble({
    super.key,
    required this.upload,
    required this.onRetry,
    required this.onCancel,
  });

  final PendingUpload upload;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.bubbleGap),
    child: Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        decoration: const BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.bubble)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            width: AppSpacing.attachmentWidth,
            height: AppSpacing.attachmentHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (upload.file.isImage)
                  Image.file(
                    File(upload.file.path),
                    fit: BoxFit.cover,
                    cacheWidth: 2 * AppSpacing.attachmentWidth.toInt(),
                    errorBuilder: (context, _, _) =>
                        const ColoredBox(color: AppColors.fill),
                  )
                else
                  _FileFace(name: upload.file.name, size: upload.file.bytes),
                Obx(
                  () => upload.isFailed.value
                      ? _Failed(
                          message: upload.error.value ?? '',
                          canRetry: upload.canRetry.value,
                          onRetry: onRetry,
                          onCancel: onCancel,
                        )
                      : _Progress(upload: upload, onCancel: onCancel),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FileFace extends StatelessWidget {
  const _FileFace({required this.name, required this.size});

  final String name;
  final int size;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.fill,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: AppSpacing.fileIcon,
            color: AppColors.cardMuted,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.message,
          ),
          Text(AttachmentTag.sizeText(size), style: AppText.caption),
        ],
      ),
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.upload, required this.onCancel});

  final PendingUpload upload;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: AppSpacing.xxs,
        right: AppSpacing.xxs,
        child: Semantics(
          button: true,
          label: 'Cancel upload',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: const SizedBox(
              width: AppSpacing.iconButton,
              height: AppSpacing.iconButton,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.scrim,
                ),
                child: Icon(Icons.close, size: 18, color: AppColors.white),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: AppSpacing.xs,
        right: AppSpacing.xs,
        bottom: AppSpacing.xs,
        child: Obx(() => AppProgressBar(value: upload.progress.value)),
      ),
    ],
  );
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.canRetry,
    required this.onRetry,
    required this.onCancel,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.scrim.withValues(alpha: 0.7),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Not sent. $message',
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppText.readable.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (canRetry) _Action(label: 'Retry', onTap: onRetry),
              _Action(label: 'Cancel', onTap: onCancel),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTapTarget,
          minHeight: AppSpacing.minTapTarget,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              label,
              style: AppText.label.copyWith(color: AppColors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
