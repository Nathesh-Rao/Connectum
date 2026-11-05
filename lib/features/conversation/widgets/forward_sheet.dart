import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/conversation.dart';
import '../../../data/models/message.dart';
import '../conversation_controller.dart';
import '../models/forward.dart';

/// "Forward to": the person's chats with a search and a choice of up to
/// [Forward.maxTargets]. Sending closes the sheet; the result is a notice.
class ForwardSheet extends StatelessWidget {
  const ForwardSheet({
    super.key,
    required this.onSend,
    required this.message,
    required this.picker,
  });

  final void Function(List<Conversation> chosen) onSend;
  final Message message;
  final ForwardPicker picker;

  static Future<void> show(
    BuildContext context,
    ConversationController controller,
    Message message,
  ) => AppBottomSheet.show<void>(
    context,
    title: 'Forward to',
    child: ForwardSheet(
      onSend: (chosen) => controller.forward(message, chosen),
      message: message,
      picker: ForwardPicker(targets: controller.forwardTargets(message)),
    ),
  );

  static String _typeLabel(Conversation c) => switch (c.kind) {
    'group' => 'Group',
    'global' => 'Everyone',
    _ => c.isEncrypted ? 'Direct message · encrypted' : 'Direct message',
  };

  @override
  Widget build(BuildContext context) {
    final p = picker;
    final maxList = MediaQuery.sizeOf(context).height * 0.4;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Forward.tagOf(message) == null
                  ? Icons.chat_bubble_outline
                  : Icons.attach_file,
              size: 16,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                Forward.previewOf(message),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.readable,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        AppTextField(
          hint: 'Search',
          leading: const Icon(Icons.search, size: 20, color: AppColors.muted),
          onChanged: (v) => p.query.value = v,
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: math.max(maxList, 160)),
          child: Obx(() {
            final rows = p.visible;
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('No chats found', style: AppText.readable),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final c = rows[i];
                return Obx(() {
                  final isOn = p.selected.contains(c.convId);
                  return Semantics(
                    selected: isOn,
                    child: AppListRow(
                      title: c.title,
                      subtitle: _typeLabel(c),
                      isSelected: isOn,
                      leading: AppAvatar(
                        name: c.title,
                        size: AppSpacing.avatarSmall,
                        isSquare: c.kind != 'dm',
                      ),
                      trailing: _SelectMark(isOn: isOn),
                      onTap: () => p.toggle(c),
                    ),
                  );
                });
              },
            );
          }),
        ),
        Obx(
          () => p.problem.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(p.problem.value!, style: AppText.error),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppButton.primary(
            label: p.sendLabel,
            leadingIcon: Icons.send_rounded,
            isCentered: true,
            onPressed: p.selected.isEmpty
                ? null
                : () {
                    final chosen = p.chosen;
                    Navigator.of(context).pop();
                    onSend(chosen);
                  },
          ),
        ),
      ],
    );
  }
}

class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.isOn});

  final bool isOn;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppCurves.out,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOn ? AppColors.accent : Colors.transparent,
        border: Border.all(
          color: isOn ? AppColors.accent : AppColors.cardMuted,
          width: 1.5,
        ),
      ),
      child: AnimatedScale(
        duration: AppDurations.fast,
        curve: AppCurves.out,
        scale: isOn ? 1 : 0,
        child: const Icon(Icons.check, size: 16, color: Colors.white),
      ),
    );
  }
}
