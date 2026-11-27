import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../data/models/self_conversation.dart';

/// One calm line in the thread when older notes are locked on this phone: it
/// says what is needed and opens the encryption setup. Not an error.
class WorkspaceLockedHint extends StatelessWidget {
  const WorkspaceLockedHint({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 14, color: AppColors.muted),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              SelfConversation.lockedNotesLine,
              style: AppText.label.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      ),
    ),
  );
}
