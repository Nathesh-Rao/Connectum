import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../core/widgets/app_tonal_icon_button.dart';
import '../models/chat_person.dart';
import '../models/person_link.dart';

/// One person in New chat: avatar, name, secondary text and the action that
/// fits the link: a round icon button (connect, requested, chat) or the
/// "Wants to connect" tag.
class NewChatPersonRow extends StatelessWidget {
  const NewChatPersonRow({
    super.key,
    required this.person,
    required this.link,
    required this.onOpen,
    required this.onConnect,
    this.isSending = false,
  });

  final ChatPerson person;
  final PersonLink link;
  final VoidCallback onOpen;
  final VoidCallback onConnect;

  /// A connection request is on its way: the circle shows a progress ring.
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    final caption = person.detail.isNotEmpty
        ? person.detail
        : person.source == 'conversation'
        ? null
        : '@${person.username}';
    return Semantics(
      container: true,
      label: '${person.name}, ${_words(link)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.settingRowHeight,
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              AppAvatar(
                name: person.name,
                kind: AppAvatarKind.person,
                picture: person.avatar,
                size: AppSpacing.avatarSmall,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: AppText.readableStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (caption != null)
                      Text(
                        caption,
                        style: AppText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (link == PersonLink.asked)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                  ),
                  child: const AppTag(
                    label: 'Wants to connect',
                    tone: AppTagTone.accent,
                  ),
                )
              else
                _action(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action() {
    switch (link) {
      case PersonLink.connected:
        return const SizedBox(height: AppSpacing.minTapTarget);
      case PersonLink.requested:
        return AppTonalIconButton(
          icon: Icons.hourglass_empty,
          tone: AppTones.violet,
          label: 'Requested',
          isDimmed: true,
          isBusy: isSending,
        );
      default:
        return AppTonalIconButton(
          icon: Icons.person_add_outlined,
          tone: AppTones.blue,
          label: 'Connect',
          onPressed: onConnect,
          isBusy: isSending,
        );
    }
  }

  static String _words(PersonLink link) => switch (link) {
    PersonLink.connected => 'connected',
    PersonLink.requested => 'request sent',
    PersonLink.asked => 'wants to connect with you',
    PersonLink.none => 'not connected',
  };
}
