import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../form_controller.dart';
import '../form_rules.dart';
import '../models/field_input.dart';
import 'form_box.dart';

/// The files of a file field: each is uploaded as soon as it is chosen, and
/// the record keeps the ids. One file, or up to ten when the field takes
/// several.
class FormFileField extends StatelessWidget {
  const FormFileField({
    super.key,
    required this.controller,
    required this.input,
  });

  final FormController controller;
  final FieldInput input;

  static const _limitNote = 'Up to 10 MB each';

  @override
  Widget build(BuildContext context) {
    final f = input.def;
    final max = FormRules.maxFiles(f);
    return Obx(() {
      final items = input.files.toList();
      final canAdd = f.isMulti ? items.length < max : true;
      final error = input.error.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _FileRow(
                item: item,
                onRetry: () => controller.retryFile(input, item),
                onRemove: () => controller.removeFile(input, item),
              ),
            ),
          if (canAdd)
            FormBox(
              onTap: () => _choose(context),
              trailing: const Icon(
                Icons.attach_file,
                size: 18,
                color: AppColors.muted,
              ),
              error: input.error,
              child: Text(
                !f.isMulti && items.isNotEmpty
                    ? 'Replace file'
                    : f.isMulti && items.isNotEmpty
                    ? 'Attach another file'
                    : 'Attach a file',
                style: AppText.input.copyWith(color: AppColors.muted),
              ),
            )
          else if (error != null && error.isNotEmpty)
            Text(error, style: AppText.error),
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(_limitNote, style: AppText.caption),
          ),
        ],
      );
    });
  }

  void _choose(BuildContext context) {
    AppBottomSheet.show<void>(
      context,
      title: 'Attach a file',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(
            context,
            Icons.photo_camera_outlined,
            'Take a photo',
            AttachSource.camera,
          ),
          _option(
            context,
            Icons.photo_library_outlined,
            'Choose a photo',
            AttachSource.library,
          ),
          _option(
            context,
            Icons.description_outlined,
            'Choose a document',
            AttachSource.document,
          ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    IconData icon,
    String title,
    AttachSource source,
  ) => AppListRow(
    title: title,
    leading: Icon(icon, color: AppColors.ink),
    onTap: () {
      Navigator.of(context).pop();
      controller.addFile(input, source);
    },
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.item,
    required this.onRetry,
    required this.onRemove,
  });

  final FormFileItem item;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  static String _size(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = item.state.value;
    final error = item.error.value;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.controlAll,
        border: Border.all(
          color: state == FormFileState.failed
              ? AppColors.error
              : AppColors.inputBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.readable,
                ),
              ),
              if (_size(item.size).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(_size(item.size), style: AppText.caption),
                ),
              if (state == FormFileState.failed)
                IconButton(
                  tooltip: 'Retry',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              IconButton(
                tooltip: 'Remove file',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (state == FormFileState.uploading)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: AppProgressBar(value: item.progress.value),
            ),
          if (state == FormFileState.failed && error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(error, style: AppText.error),
            ),
        ],
      ),
    );
  });
}
