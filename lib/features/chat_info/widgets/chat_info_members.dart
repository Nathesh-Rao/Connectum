import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../tickets/widgets/ticket_status_pill.dart';
import '../models/chat_info.dart';

/// "Members (N)", a search field when there are more than
/// [ChatInfoData.searchThreshold], and one row per person. The text field
/// belongs to this State and is disposed with it.
class ChatInfoMembers extends StatefulWidget {
  const ChatInfoMembers({
    super.key,
    required this.members,
    required this.hasSearch,
    required this.onOpen,
    this.onAddPeople,
    this.pictureOf,
  });

  final List<ChatInfoMember> members;
  final bool hasSearch;
  final ValueChanged<ChatInfoMember> onOpen;

  /// Only given to the group's owner (it already exists in the app).
  final VoidCallback? onAddPeople;
  final String? Function(String username)? pictureOf;

  @override
  State<ChatInfoMembers> createState() => _ChatInfoMembersState();
}

class _ChatInfoMembersState extends State<ChatInfoMembers> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Members (${widget.members.length})', style: AppText.subtitle),
        if (widget.onAddPeople != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Add people',
            onPressed: widget.onAddPeople,
          ),
        ],
        if (widget.hasSearch) ...[
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: _query,
            hint: 'Search members',
            leading: const Icon(Icons.search, size: 20, color: AppColors.muted),
          ),
        ],
        const SizedBox(height: AppSpacing.xxs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _query,
          builder: (context, value, _) {
            final shown = [
              for (final m in widget.members)
                if (m.matches(value.text)) m,
            ];
            if (shown.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'No one matches that.',
                  style: AppText.readable.copyWith(color: AppColors.muted),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  _MemberRow(
                    member: shown[i],
                    hasDivider: i > 0,
                    pictureOf: widget.pictureOf,
                    onTap: shown[i].isMe ? null : () => widget.onOpen(shown[i]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.hasDivider,
    required this.onTap,
    this.pictureOf,
  });

  final String? Function(String username)? pictureOf;
  final ChatInfoMember member;
  final bool hasDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    return Semantics(
      button: onTap != null,
      label:
          '${m.name}, ${m.handle}${m.isOwner ? ', owner' : ''}'
          '${m.isMe ? ', you' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            border: hasDivider
                ? const Border(top: BorderSide(color: AppColors.line))
                : null,
          ),
          child: Row(
            children: [
              if (pictureOf == null)
                AppAvatar(
                  name: m.name,
                  kind: AppAvatarKind.person,
                  size: AppSpacing.avatarSmall,
                )
              else
                Obx(
                  () => AppAvatar(
                    name: m.name,
                    kind: AppAvatarKind.person,
                    picture: pictureOf!(m.user),
                    size: AppSpacing.avatarSmall,
                  ),
                ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.readableStrong,
                    ),
                    Text(
                      m.handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              if (m.isOwner) ...[
                const SizedBox(width: AppSpacing.xs),
                const TicketPill(
                  label: 'Owner',
                  icon: Icons.shield_outlined,
                  tone: AppTones.slate,
                ),
              ],
              if (m.isMe) ...[
                const SizedBox(width: AppSpacing.xs),
                const Text('You', style: AppText.caption),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
