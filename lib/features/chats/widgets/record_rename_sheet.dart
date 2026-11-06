import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/conversation.dart';
import '../../../data/models/thread_names.dart';
import '../chats_controller.dart';
import '../record_rename_controller.dart';

/// Rename a record conversation for everyone in it. The text field belongs to
/// this State and is disposed with it.
class RecordRenameSheet extends StatefulWidget {
  const RecordRenameSheet({
    super.key,
    required this.rename,
    required this.initialName,
  });

  final RecordRenameController rename;
  final String initialName;

  static Future<void> show(
    BuildContext context,
    ChatsController controller,
    Conversation conversation,
  ) => AppBottomSheet.show<void>(
    context,
    title: 'Rename conversation',
    child: RecordRenameSheet(
      rename: controller.renameFor(conversation),
      initialName: conversation.title,
    ),
  );

  @override
  State<RecordRenameSheet> createState() => _RecordRenameSheetState();
}

class _RecordRenameSheetState extends State<RecordRenameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final isDone = await widget.rename.save(_name.text);
    if (isDone && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rename;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => AppTextField(
            controller: _name,
            label: 'Name',
            hint: 'Conversation name',
            errorText: r.error.value,
            maxLength: RecordRename.maxLength,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            enabled: !r.isSaving.value,
            onChanged: (_) => r.clearError(),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Everyone in it sees the new name. Leave it empty to bring the original title back.',
          style: AppText.readable.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppButton.primary(
            label: 'Save',
            isCentered: true,
            isLoading: r.isSaving.value,
            onPressed: r.isSaving.value ? null : _save,
          ),
        ),
      ],
    );
  }
}
