import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';
import '../models/mention_picker.dart';

/// The "@" list of a group's message box: a compact card right above the box
/// (so above the keyboard), at most six rows. A tap chooses; back closes it.
/// Nothing shows while there is no match.
class MentionPanel extends StatelessWidget {
  const MentionPanel({
    super.key,
    required this.rows,
    required this.onPick,
    required this.onClose,
    this.pictureOf,
  });

  final RxList<MentionPerson> rows;
  final ValueChanged<MentionPerson> onPick;
  final VoidCallback onClose;

  /// A person's picture address by username; read inside the Obx.
  final String? Function(String username)? pictureOf;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AppDurations.fast,
    curve: AppCurves.out,
    alignment: Alignment.bottomCenter,
    child: Obx(() {
      final people = rows.toList();
      if (people.isEmpty) return const SizedBox(width: double.infinity);
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) => onClose(),
        child: Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            0,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadius.control),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in people)
                InkWell(
                  key: ValueKey(p.username),
                  onTap: () => onPick(p),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSpacing.minTapTarget,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          AppAvatar(
                            name: p.label,
                            picture: pictureOf?.call(p.username),
                            size: AppSpacing.avatarSmall,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              p.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.readableStrong,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text('@${p.username}', style: AppText.caption),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }),
  );
}
