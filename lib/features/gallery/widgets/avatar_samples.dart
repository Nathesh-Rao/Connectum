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
