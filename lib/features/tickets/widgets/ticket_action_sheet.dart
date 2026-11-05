import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/ticket.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../../chats/models/chat_person.dart';
import '../../forms/models/field_input.dart';
import '../../tasks/widgets/task_people_sheet.dart';
import '../ticket_action_form.dart';
import '../ticket_detail_controller.dart';
import '../tickets_texts.dart';

/// One action: only the inputs it asks for, and a hint of where the ticket
/// goes. Send waits until a required input is filled in. A stale or refused
/// send keeps the sheet open with what was typed.
class TicketActionSheet extends StatelessWidget {
  const TicketActionSheet({
    super.key,
    required this.controller,
    required this.form,
  });

  final TicketDetailController controller;
  final TicketActionForm form;

  static Future<void> show(
    BuildContext context,
    TicketDetailController controller,
    TicketAction action,
  ) {
    final form = controller.newForm(action);
    return AppBottomSheet.show<void>(
      context,
      title: action.name,
      child: TicketActionSheet(controller: controller, form: form),
    ).whenComplete(form.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final f = form;
    final a = f.action;
    final hint = TicketsTexts.assignHint(a.assign);
    return Obx(() {
      final isStillOffered = c.actions.any((x) => x.name == a.name);
      final problem = f.problem;
      final isBusy = c.isBusy.value;
      final error = f.error.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(hint, style: AppText.readable),
            ),
          if (!isStillOffered)
            const _Gap(Text(TicketsTexts.actionGone, style: AppText.error)),
          if (a.asksReason)
            _Gap(a.reasons.isEmpty ? _reasonField(f) : _reasonChoice(f)),
          if (a.asksRemarks) _Gap(_remarksField(f)),
          if (a.asksSendTo) _Gap(_sendTo(context, c, f)),
          if (a.asksPercent) _Gap(_percent(f)),
          if (a.percent == 'hundred')
            const _Gap(
              Text(TicketsTexts.percentHundred, style: AppText.bodyStrong),
            ),
          if (a.asksFiles) _Gap(_Files(controller: c, form: f)),
          if (error != null) _Gap(Text(error, style: AppText.error)),
          AppButton.primary(
            label: a.name,
            isCentered: true,
            isLoading: isBusy,
            onPressed: isBusy || problem != null || !isStillOffered
                ? null
                : () async {
                    final isDone = await c.submit(f);
                    if (isDone && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
          ),
        ],
      );
    });
  }

  Widget _reasonField(TicketActionForm f) => AppTextField(
    controller: f.reasonText,
    label: TicketsTexts.reasonField,
    hint: f.action.reason == 'required'
        ? TicketsTexts.reasonRequiredHint
        : TicketsTexts.reasonHint,
    minLines: 1,
    maxLines: 3,
    onChanged: (v) => f.reason.value = v,
  );

  Widget _reasonChoice(TicketActionForm f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(TicketsTexts.reasonField, style: AppText.readableStrong),
      const SizedBox(height: AppSpacing.xxs),
      for (final r in f.action.reasons)
        AppListRow(
          title: r,
          minHeight: AppSpacing.settingRowHeight,
          isSelected: f.reason.value == r,
          trailing: f.reason.value == r
              ? const Icon(Icons.check, size: 18, color: AppColors.accent)
              : null,
          onTap: () => f.reason.value = r,
        ),
    ],
  );

  Widget _remarksField(TicketActionForm f) => AppTextField(
    controller: f.remarks,
    label: TicketsTexts.remarksField,
    hint: f.action.remarks == 'required'
        ? TicketsTexts.remarksRequiredHint
        : TicketsTexts.remarksHint,
    minLines: 2,
    maxLines: 5,
    onChanged: (v) => f.remarksText.value = v,
  );

  Widget _sendTo(
    BuildContext context,
    TicketDetailController c,
    TicketActionForm f,
  ) {
    final person = f.sendTo.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(TicketsTexts.sendToField, style: AppText.readableStrong),
        const SizedBox(height: AppSpacing.xxs),
        AppButton.secondary(
          label: person == null ? TicketsTexts.sendToPick : person.name,
          onPressed: () => _pick(context, c, f),
        ),
      ],
    );
  }

  Future<void> _pick(
    BuildContext context,
    TicketDetailController c,
    TicketActionForm f,
  ) {
    final people = c.newPeople()..load();
    ChatPerson? picked;
    return AppBottomSheet.show<void>(
      context,
      title: TicketsTexts.sendToTitle,
      child: TaskPeopleSheet(
        people: people,
        onPick: (p) {
          picked = p;
          Navigator.of(context).pop();
        },
      ),
    ).whenComplete(() {
      people.close();
      final p = picked;
      if (p != null) c.picked(f, p);
    });
  }

  Widget _percent(TicketActionForm f) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              TicketsTexts.percentField,
              style: AppText.readableStrong,
            ),
          ),
          Text(
            TicketsTexts.percentValue(f.percent.value),
            style: AppText.bodyStrong,
          ),
        ],
      ),
      Slider(
        value: f.percent.value.toDouble(),
        max: 100,
        divisions: 100,
        activeColor: AppColors.accent,
        inactiveColor: AppColors.line,
        onChanged: (v) => f.percent.value = v.round(),
      ),
    ],
  );
}

class _Files extends StatelessWidget {
  const _Files({required this.controller, required this.form});

  final TicketDetailController controller;
  final TicketActionForm form;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = form.files.toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            form.action.attachments == 'required'
                ? '${TicketsTexts.filesLabel} *'
                : TicketsTexts.filesLabel,
            style: AppText.readableStrong,
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _FileRow(
                item: item,
                onRetry: () => controller.retryFile(form, item),
                onRemove: () => controller.removeFile(form, item),
              ),
            ),
          AppButton.secondary(
            label: items.isEmpty
                ? TicketsTexts.attach
                : TicketsTexts.attachAnother,
            icon: Icons.attach_file,
            onPressed: () => _choose(context),
          ),
        ],
      );
    });
  }

  void _choose(BuildContext context) {
    AppBottomSheet.show<void>(
      context,
      title: TicketsTexts.attach,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(
            context,
            Icons.photo_camera_outlined,
            TicketsTexts.attachPhoto,
            AttachSource.camera,
          ),
          _option(
            context,
            Icons.photo_library_outlined,
            TicketsTexts.attachLibrary,
            AttachSource.library,
          ),
          _option(
            context,
            Icons.description_outlined,
            TicketsTexts.attachDocument,
            AttachSource.document,
          ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context,
    IconData icon,
    String title,
    AttachSource source,
  ) => AppListRow(
    title: title,
    leading: Icon(icon, color: AppColors.ink),
    onTap: () {
      Navigator.of(context).pop();
      controller.addFile(form, source);
    },
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.item,
    required this.onRetry,
    required this.onRemove,
  });

  final FormFileItem item;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = item.state.value;
    final error = item.error.value;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.controlAll,
        border: Border.all(
          color: state == FormFileState.failed
              ? AppColors.error
              : AppColors.inputBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.readable,
                ),
              ),
              if (state == FormFileState.failed)
                IconButton(
                  tooltip: TicketsTexts.retry,
                  visualDensity: VisualDensity.compact,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              IconButton(
                tooltip: TicketsTexts.removeFile,
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (state == FormFileState.uploading)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: AppProgressBar(value: item.progress.value),
            ),
          if (state == FormFileState.failed && error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(error, style: AppText.error),
            ),
        ],
      ),
    );
  });
}

class _Gap extends StatelessWidget {
  const _Gap(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: child,
  );
}
