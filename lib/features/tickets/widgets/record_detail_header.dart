import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/chat_time.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_skeleton.dart';

/// Who raised the record and when, with its subject: the block under the top
/// bar of the record screen.
class RecordIdentity extends StatelessWidget {
  const RecordIdentity({
    super.key,
    required this.name,
    required this.subject,
    required this.ts,
    this.picture,
  });

  final String name;
  final String? picture;
  final String subject;

  /// Epoch ms; 0 hides the date and the time.
  final int ts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                name: name,
                size: AppSpacing.avatarSmall,
                picture: picture,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppText.inboxName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ts > 0)
                      Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          _Meta(
                            icon: Icons.calendar_today_outlined,
                            text: ChatTime.date(ts),
                            label: 'Date',
                          ),
                          _Meta(
                            icon: Icons.schedule_rounded,
                            text: ChatTime.time(ts),
                            label: 'Time',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (subject.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(subject, style: AppText.subtitle),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.label});

  final IconData icon;
  final String text;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $text',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSpacing.inboxMetaIcon, color: AppColors.muted),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            text,
            style: AppText.inboxMeta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// The record screen while it reads: the shapes of the identity, the strip
/// and a few field lines, pulsing together.
class RecordDetailSkeleton extends StatelessWidget {
  const RecordDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonScope(
      child: Padding(
        key: const ValueKey('record-skeleton'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: const [
                AppSkeleton(
                  width: AppSpacing.avatarSmall,
                  height: AppSpacing.avatarSmall,
                  isCircle: true,
                ),
                SizedBox(width: AppSpacing.xs),
                Expanded(child: AppSkeleton(height: 16)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const AppSkeleton(height: AppSpacing.inboxStripHeight),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < 4; i++) ...[
              Row(
                children: const [
                  AppSkeleton(
                    width: AppSpacing.inboxFieldIcon,
                    height: AppSpacing.inboxFieldIcon,
                    radius: AppRadius.control,
                  ),
                  SizedBox(width: AppSpacing.xs),
                  Expanded(child: AppSkeleton(height: 28)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
