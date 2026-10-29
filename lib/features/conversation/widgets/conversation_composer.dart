import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/message.dart';
import '../conversation_controller.dart';

/// The composer: a field that grows to five lines, a send button that wakes
/// as text appears, and attach and forms buttons that are placeholders for
/// now. In an encrypted thread it is replaced by a blocked state.
class ConversationComposer extends StatelessWidget {
  const ConversationComposer({super.key, required this.controller});

  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (c.isBlocked.value) return const _Blocked();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(() {
            final note = c.notice.value;
            final n = c.length.value;
            final text = n > ConversationController.maxLength
                ? 'Messages can be up to ${ConversationController.maxLength} characters.'
                : note;
            if (text == null && n < 1800) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xxs,
                AppSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text ?? '',
                      style: n > ConversationController.maxLength
                          ? AppText.error
                          : AppText.caption,
                    ),
                  ),
                  if (n >= 1800)
                    Text(
                      '$n/${ConversationController.maxLength}',
                      style: n > ConversationController.maxLength
                          ? AppText.error
                          : AppText.caption,
                    ),
                ],
              ),
            );
          }),
          Obx(() => _ReplyBar(message: c.reply.value, onClose: c.clearReply)),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.composerPad),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.line),
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadius.bubble),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Placeholder(
                    icon: Icons.add,
                    label: 'Attach',
                    onTap: c.tapPlaceholder,
                  ),
                  _Placeholder(
                    icon: Icons.grid_view,
                    label: 'Forms',
                    onTap: c.tapPlaceholder,
                  ),
                  Expanded(
                    child: AppTextField(
                      controller: c.text,
                      focusNode: c.focus,
                      hint: 'Type a message…',
                      minLines: 1,
                      maxLines: 5,
                      minHeight: AppSpacing.composerButton,
                      horizontalPadding: AppSpacing.xxs,
                      fillColor: Colors.transparent,
                      hasFocusRing: false,
                      borderColor: Colors.transparent,
                      borderRadius: BorderRadius.zero,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: c.onChanged,
                    ),
                  ),
                  Obx(() {
                    final isActive = c.length.value > 0 && c.canSend;
                    return _SendButton(isActive: isActive, onTap: c.send);
                  }),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Coming soon',
    triggerMode: TooltipTriggerMode.tap,
    child: Semantics(
      label: '$label, coming soon',
      excludeSemantics: true,
      child: SizedBox(
        width: AppSpacing.composerButton,
        height: AppSpacing.composerButton,
        child: Icon(icon, size: 22, color: AppColors.cardMuted),
      ),
    ),
  );
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: isActive,
    label: 'Send',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isActive ? onTap : null,
      child: SizedBox(
        width: AppSpacing.composerButton,
        height: AppSpacing.composerButton,
        child: Center(
          child: AnimatedContainer(
            duration: AppDurations.fast,
            curve: AppCurves.out,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppColors.accent : AppColors.cardChip,
            ),
            child: Icon(
              Icons.arrow_upward,
              size: 18,
              color: isActive ? AppColors.background : AppColors.cardMuted,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.message, required this.onClose});

  final Message? message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return AnimatedSize(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: m == null
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                0,
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xxs,
                AppSpacing.xs,
              ),
              decoration: const BoxDecoration(
                color: AppColors.bubbleIn,
                borderRadius: BorderRadius.all(
                  Radius.circular(AppRadius.control),
                ),
                border: Border(
                  left: BorderSide(color: AppColors.accent, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.isMine ? 'You' : m.sender,
                          style: AppText.label.copyWith(
                            color: AppColors.accentInk,
                          ),
                        ),
                        Text(
                          m.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Cancel reply',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: onClose,
                      child: const SizedBox(
                        width: AppSpacing.composerButton,
                        height: AppSpacing.composerButton,
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.page,
      vertical: AppSpacing.sm,
    ),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      children: [
        const AppStateImage(
          kind: AppStateImageKind.locked,
          size: AppSpacing.stateImageRow,
          isAnimated: false,
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Text(
            "Can't send in encrypted chats from mobile yet",
            style: AppText.readable,
          ),
        ),
      ],
    ),
  );
}
