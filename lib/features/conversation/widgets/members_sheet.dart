import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';

/// The members of a group as the stored list has them. Read only.
class MembersSheet extends StatelessWidget {
  const MembersSheet({
    super.key,
    required this.members,
    required this.me,
    this.onAddPeople,
  });

  final List<String> members;
  final String me;

  /// Only given to the group's owner.
  final VoidCallback? onAddPeople;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required List<String> members,
    required String me,
    VoidCallback? onAddPeople,
  }) => AppBottomSheet.show<void>(
    context,
    title: title,
    child: MembersSheet(members: members, me: me, onAddPeople: onAddPeople),
  );

  @override
  Widget build(BuildContext context) {
    final sorted = [...members]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${sorted.length} members', style: AppText.caption),
        if (onAddPeople != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Add people', onPressed: onAddPeople),
        ],
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < sorted.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : const Border(top: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                AppAvatar(name: sorted[i], size: AppSpacing.avatarSmall),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(sorted[i], style: AppText.readableStrong)),
                if (sorted[i].toLowerCase() == me.toLowerCase())
                  Text('You', style: AppText.caption),
              ],
            ),
          ),
      ],
    );
  }
}
