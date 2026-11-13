import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';

/// Debug only: 40 sample names in the three avatar kinds, to judge the
/// palette on a phone.
class AvatarSamples extends StatelessWidget {
  const AvatarSamples({super.key});

  static const names = [
    'Priya Sharma',
    'Arjun',
    'Meera Nair',
    'Rahul Verma',
    'Sana Khan',
    'Tom',
    'Ana Lopez',
    'Wei Chen',
    'Omar Haddad',
    'Zoe',
    'A',
    'b',
    'Z',
    'Q',
    'M',
    'Billing Team',
    'Customer Support',
    'Ops',
    'Night Shift Floor 3',
    'HR',
    'Ticket #12: Printer jams on floor two',
    'Ticket #7: VPN',
    'Ticket #301: Refund',
    'Procurement and Vendor Management Committee',
    'Dev Patel',
    'अर्जुन मेहता',
    'प्रिया',
    '李雷',
    '王小明',
    'தமிழ்',
    'Éva Åberg',
    'Ørjan',
    'Ñandú',
    'محمد',
    'Иван',
    '😀 Party',
    '🚀',
    '  padded name  ',
    '',
    '#hash',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Picture states', style: AppText.bodyStrong),
        ),
        const SizedBox(height: AppSpacing.xs),
        const Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            _PictureState(
              'picture',
              AppAvatar(
                name: 'Asha Rao',
                kind: AppAvatarKind.person,
                picture: 'asset:assets/debug/avatars/demo_1.png',
              ),
            ),
            _PictureState(
              'none',
              AppAvatar(name: 'Asha Rao', kind: AppAvatarKind.person),
            ),
            _PictureState(
              'broken',
              AppAvatar(
                name: 'Asha Rao',
                kind: AppAvatarKind.person,
                picture: 'asset:assets/debug/avatars/missing.png',
              ),
            ),
            _PictureState(
              'plain',
              AppAvatar(
                name: 'Asha Rao',
                picture: 'asset:assets/debug/avatars/demo_2.png',
              ),
            ),
            _PictureState(
              'group',
              AppAvatar(
                name: 'Design',
                kind: AppAvatarKind.group,
                picture: 'asset:assets/debug/avatars/demo_3.png',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final name in names)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                AppAvatar(name: name, kind: AppAvatarKind.person),
                const SizedBox(width: AppSpacing.xs),
                AppAvatar(name: name, kind: AppAvatarKind.group),
                const SizedBox(width: AppSpacing.xs),
                AppAvatar(name: name, kind: AppAvatarKind.ticket),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    name.isEmpty ? '(empty)' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.readable,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PictureState extends StatelessWidget {
  const _PictureState(this.label, this.avatar);

  final String label;
  final Widget avatar;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      avatar,
      const SizedBox(height: AppSpacing.xxs),
      Text(label, style: AppText.readable),
    ],
  );
}
