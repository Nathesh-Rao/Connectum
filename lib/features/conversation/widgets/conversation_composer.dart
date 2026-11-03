import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/attachment_tag.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_state_image.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/message.dart';
import '../../forms/widgets/forms_picker_sheet.dart';
import '../conversation_controller.dart';
import 'attach_sheet.dart';
import 'commands_panel.dart';
import 'key_change_sheet.dart';

/// The composer: a field that grows to five lines, a send button that wakes
/// as text appears, an attach button for photos and the forms button. In an
/// encrypted thread the lock and the hint "Encrypted message" show; where a send can never work (the peer has no encryption set
/// up, a security key changed) the field is replaced by a note saying why, and
/// the forms button stays.
class ConversationComposer extends StatelessWidget {
  const ConversationComposer({super.key, required this.controller});

  final ConversationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      if (c.isBlocked.value) return _Blocked(controller: c);
      final isLocked = c.isLocked.value;
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
          CommandsPanel(
            prompt: c.prompt,
            onPick: c.pickCommand,
            isOnline: () => c.commands.isOnline,
          ),
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
                  _AttachButton(
                    reason: c.attachBlock,
                    onTap: () {
                      if (c.tapAttach()) AttachSheet.show(context, c);
                    },
                  ),
                  FormsButton(
                    onTap: () => FormsPickerSheet.show(context, c.picker),
                  ),
                  if (isLocked)
                    const SizedBox(
                      height: AppSpacing.composerButton,
                      child: Padding(
                        padding: EdgeInsets.only(left: AppSpacing.xxs),
                        child: Icon(
                          Icons.lock,
                          size: AppSpacing.statusIcon,
                          color: AppColors.yesText,
                          semanticLabel: 'End-to-end encrypted',
                        ),
                      ),
                    ),
                  Expanded(
                    child: AppTextField(
                      controller: c.text,
                      focusNode: c.focus,
                      hint: isLocked
                          ? 'Encrypted message'
                          : "Type a message or '#' for commands…",
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
                    return ComposerSendButton(
                      isActive: isActive,
                      onTap: c.send,
                    );
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

/// The attach button. Where photos cannot be sent (an encrypted thread, a
/// team, the global room) it is dimmed and says why; a tap shows the reason.
class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.reason, required this.onTap});

  final String? reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = reason != null;
    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: isDisabled ? 'Attach, $reason' : 'Attach',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: AppSpacing.composerButton,
          height: AppSpacing.composerButton,
          child: Icon(
            Icons.add,
            size: 22,
            color: isDisabled ? AppColors.cardMuted : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class ComposerSendButton extends StatelessWidget {
  const ComposerSendButton({
    super.key,
    required this.isActive,
    required this.onTap,
  });

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
                          AttachmentTag.preview(m.text) ?? m.text,
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

/// The forms button of every composer: it opens the forms sheet, in an
/// encrypted conversation too (forms are not end-to-end encrypted).
class FormsButton extends StatelessWidget {
  const FormsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Forms',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox(
        width: AppSpacing.composerButton,
        height: AppSpacing.composerButton,
        child: Icon(Icons.grid_view, size: 22, color: AppColors.ink),
      ),
    ),
  );
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.controller});

  final ConversationController controller;

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
        Expanded(
          child: Obx(
            () => Text(
              controller.blockReason.value ??
                  "Can't send in this encrypted chat yet",
              style: AppText.readable,
            ),
          ),
        ),
        Obx(
          () => controller.isKeyChange.value
              ? AppButton.text(
                  label: 'Review key',
                  tone: AppTextButtonTone.accent,
                  isLoading: controller.isReviewing.value,
                  onPressed: () => KeyChangeSheet.open(context, controller),
                )
              : const SizedBox.shrink(),
        ),
        FormsButton(
          onTap: () => FormsPickerSheet.show(context, controller.picker),
        ),
      ],
    ),
  );
}
