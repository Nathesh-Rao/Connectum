import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../data/profile_photo/profile_photo_picker.dart';

/// Take a photo, choose one, or remove the current one. Each choice closes
/// the sheet and hands over to [onCamera], [onGallery] or [onRemove].
class ProfilePhotoSheet extends StatelessWidget {
  const ProfilePhotoSheet({
    super.key,
    required this.hasPhoto,
    required this.onPick,
    required this.onRemove,
  });

  final bool hasPhoto;
  final void Function(PhotoSource source) onPick;
  final VoidCallback onRemove;

  void _choose(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppListRow(
        title: 'Take photo',
        leading: const Icon(
          Icons.photo_camera_outlined,
          color: AppColors.primary,
        ),
        onTap: () => _choose(context, () => onPick(PhotoSource.camera)),
      ),
      AppListRow(
        title: 'Choose from gallery',
        leading: const Icon(
          Icons.photo_library_outlined,
          color: AppColors.primary,
        ),
        onTap: () => _choose(context, () => onPick(PhotoSource.gallery)),
      ),
      if (hasPhoto)
        AppListRow(
          title: 'Remove photo',
          leading: const Icon(Icons.delete_outline, color: AppColors.error),
          onTap: () => _choose(context, onRemove),
        ),
      const SizedBox(height: AppSpacing.xs),
    ],
  );
}
