import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_tones.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_progress_bar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/record_state.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../../../data/records/record_commands.dart';
import '../../chats/models/chat_person.dart';
import '../../forms/models/field_input.dart';
import '../../tasks/widgets/task_people_sheet.dart';
import '../models/ticket_action_style.dart';
import '../ticket_action_form.dart';
import '../ticket_detail_controller.dart';
import '../tickets_texts.dart';

/// The status sheet and the send sheet of one record. Both open from an item
/// of `record.actions`; a disabled item opens with its `why` and a disabled
/// button. Fields marked required by the record are mandatory, with the
/// server's wording; a stale or refused action keeps the sheet open with what
/// was typed, and the sheet follows the record read again.
class TicketActionSheet extends StatelessWidget {
  const TicketActionSheet({
    super.key,
    required this.controller,
    required this.form,
  });

  final TicketDetailController controller;
  final TicketActionForm form;

  /// Opens the sheet of item [kind] (`status` or `send`). Does nothing when
  /// the record has not been read or does not offer the item.
  static Future<void> show(
    BuildContext context,
    TicketDetailController controller,
    String kind,
  ) {
    final item = controller.item(kind);
    if (item == null) return Future.value();
    final form = controller.newForm(kind);
    return AppBottomSheet.show<void>(
      context,
      title: item.label,
      titleWidget: TicketSheetTitle(item: item),
      child: TicketActionSheet(controller: controller, form: form),
      onDispose: form.dispose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final f = form;
    return Obx(() {
      final item = c.item(f.kind);
      final isOffered = item != null;
      final isEnabled = item?.isEnabled ?? false;
      final problem = f.problem;
      final isBusy = c.isBusy.value;
      final isWaiting = isBusy || c.isCooling.value;
      final error = f.error.value;
      final s = c.state.value ?? f.state;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isOffered)
            const _Gap(Text(TicketsTexts.actionGone, style: AppText.error))
          else if (!isEnabled && item.why.isNotEmpty)
            _Gap(Text(item.why, style: AppText.error)),
          if (f.isStatus) ..._statusFields(s),
          if (f.isSend) ..._sendFields(context),
          if (error != null && error != item?.why)
            _Gap(Text(error, style: AppText.error)),
          if (f.isStatus)
            Obx(
              () => f.isFinalPicked && f.hasFinalRules
                  ? const _Gap(_ClosingWarning())
                  : const SizedBox.shrink(),
            ),
          AppButton.primary(
            label: item?.label ?? TicketsTexts.sheetSend,
            leadingIcon: actionStyleFor(item?.label ?? f.kind).icon,
            isCentered: true,
            isLoading: isBusy,
            onPressed: isWaiting || !isOffered || !isEnabled || problem != null
                ? null
                : () async {
                    final result = await c.submit(f);
                    if (!context.mounted) return;
                    if (result == ActionResult.done) {
                      Navigator.of(context).pop();
                    } else if (result == ActionResult.gone) {
                      Navigator.of(context).pop();
                      c.leave();
                    }
                  },
          ),
        ],
      );
    });
  }

  // ---- status ----------------------------------------------------------------

  List<Widget> _statusFields(RecordState s) {
    final f = form;
    return [
      _Gap(_statusPicker(s)),
      _Gap(
        _Labeled(
          icon: Icons.notes,
          label: _marked(TicketsTexts.commentsField, s.isCommentsRequired),
          child: AppTextField(
            controller: f.comments,
            hint: TicketsTexts.commentsHint,
            minLines: 2,
            maxLines: 5,
            maxLength: RecordLimits.maxText,
            onChanged: (v) => f.commentsText.value = v,
          ),
        ),
      ),
      _Gap(_percent(s)),
      _Gap(
        _Labeled(
          icon: Icons.schedule,
          label: _marked(TicketsTexts.hoursField, s.isHoursRequired),
          child: AppTextField(
            controller: f.hours,
            hint: TicketsTexts.hoursHint,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            maxLength: 5,
            onChanged: (v) => f.hoursText.value = v,
          ),
        ),
      ),
      _Gap(
        _Files(controller: controller, form: f, isRequired: s.isFilesRequired),
      ),
    ];
  }

  Widget _statusPicker(RecordState s) {
    final f = form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(
          icon: Icons.flag_outlined,
          label: TicketsTexts.statusField,
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (final name in s.statuses)
          Obx(() {
            final isPicked = f.statusPick.value == name;
            return AppListRow(
              title: s.finalStatuses.contains(name)
                  ? '$name${TicketsTexts.finalSuffix}'
                  : name,
              minHeight: AppSpacing.settingRowHeight,
              isSelected: isPicked,
              trailing: isPicked
                  ? const Icon(
                      Icons.check,
                      size: 18,
                      color: AppColors.primaryBright,
                    )
                  : null,
              onTap: () => f.pickStatus(name),
            );
          }),
      ],
    );
  }

  Widget _percent(RecordState s) {
    final f = form;
    const tone = AppTones.blue;
    return Obx(() {
      final value = f.percent.value;
      final floor = f.minPercent;
      final locked = f.lockedBelow;
      final isLocked = f.isPercentLocked || f.isPercentFixed;
      final reopening = f.isReopening.value;
      final refusal = f.percentError.value;
      final duration = f.isPercentJump.value
          ? AppDurations.reduced
          : Duration.zero;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _FieldLabel(
                  icon: Icons.speed,
                  label: _marked(
                    TicketsTexts.percentField,
                    s.isCompletionRequired,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: tone.tint,
                  borderRadius: AppRadius.pillAll,
                ),
                child: Text(
                  value == null
                      ? TicketsTexts.percentNotSet
                      : TicketsTexts.percentValue(value),
                  style: AppText.label.copyWith(color: tone.strong),
                ),
              ),
            ],
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: (value ?? floor).toDouble()),
            duration: duration,
            builder: (context, shown, _) => SliderTheme(
              data: SliderTheme.of(
                context,
              ).copyWith(trackShape: _LockedTrackShape(lockedBelow: locked)),
              child: Slider(
                value: shown.clamp(0, 100),
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: tone.solid,
                inactiveColor: tone.tint,
                semanticFormatterCallback: (v) =>
                    TicketsTexts.percentSemantics(v.round(), floor),
                onChanged: isLocked ? null : (v) => f.setPercent(v.round()),
              ),
            ),
          ),
          if (refusal != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(refusal, style: AppText.error),
            )
          else if (reopening)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                TicketsTexts.reopenHint,
                style: AppText.caption.copyWith(color: AppColors.muted),
              ),
            ),
          if (locked != null)
            Semantics(
              label: TicketsTexts.percentLockedSemantics(locked),
              excludeSemantics: true,
              child: Align(
                alignment: Alignment(locked / 50 - 1, 0),
                child: Text(
                  TicketsTexts.percentWas(locked),
                  style: AppText.caption.copyWith(color: AppColors.muted),
                ),
              ),
            ),
        ],
      );
    });
  }

  // ---- send ------------------------------------------------------------------

  List<Widget> _sendFields(BuildContext context) {
    final f = form;
    return [
      _Gap(_sendTo(context)),
      _Gap(
        _Labeled(
          icon: Icons.help_outline,
          label: TicketsTexts.reasonField,
          child: AppTextField(
            controller: f.reason,
            hint: TicketsTexts.reasonHint,
            minLines: 1,
            maxLines: 3,
            maxLength: RecordLimits.maxText,
            onChanged: (v) => f.reasonText.value = v,
          ),
        ),
      ),
      _Gap(
        _Labeled(
          icon: Icons.notes,
          label: TicketsTexts.remarksField,
          child: AppTextField(
            controller: f.remarks,
            hint: TicketsTexts.remarksHint,
            minLines: 2,
            maxLines: 5,
            maxLength: RecordLimits.maxText,
            onChanged: (v) => f.remarksText.value = v,
          ),
        ),
      ),
      _Gap(_Files(controller: controller, form: f, isRequired: false)),
    ];
  }

  Widget _sendTo(BuildContext context) {
    final f = form;
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(
          icon: Icons.person_add_alt,
          label: TicketsTexts.sendToField,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Obx(() {
          final person = f.person.value;
          return AppButton.secondary(
            label: person == null ? TicketsTexts.sendToPick : person.name,
            onPressed: () => _pick(context, c, f),
          );
        }),
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
      onDispose: people.close,
    ).whenComplete(() {
      final p = picked;
      if (p != null) c.picked(f, p);
    });
  }

  static String _marked(String label, bool isRequired) =>
      isRequired ? '$label *' : label;
}

/// The slider track with the part below [lockedBelow] drawn as locked.
class _LockedTrackShape extends RoundedRectSliderTrackShape {
  const _LockedTrackShape({required this.lockedBelow});

  final int? lockedBelow;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    double additionalActiveTrackHeight = 2,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
      textDirection: textDirection,
    );
    final locked = lockedBelow;
    if (locked == null) return;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final width = rect.width * locked / 100;
    final part = textDirection == TextDirection.rtl
        ? Rect.fromLTRB(rect.right - width, rect.top, rect.right, rect.bottom)
        : Rect.fromLTRB(rect.left, rect.top, rect.left + width, rect.bottom);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(part, Radius.circular(rect.height / 2)),
      Paint()..color = AppColors.muted,
    );
  }
}

/// The notice above the button when a final status is picked.
class _ClosingWarning extends StatelessWidget {
  const _ClosingWarning();

  @override
  Widget build(BuildContext context) {
    const tone = AppTones.violet;
    return Semantics(
      container: true,
      liveRegion: true,
      label: TicketsTexts.closingWarning,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: tone.tint,
          borderRadius: AppRadius.controlAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: tone.strong),
            const SizedBox(width: AppSpacing.xs),
            const Expanded(
              child: Text(TicketsTexts.closingWarning, style: AppText.readable),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sheet's header: the item's icon in a tinted circle and its name.
class TicketSheetTitle extends StatelessWidget {
  const TicketSheetTitle({super.key, required this.item});

  final RecordActionItem item;

  @override
  Widget build(BuildContext context) {
    final style = actionStyleFor(item.label);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: style.tone.tint,
            shape: BoxShape.circle,
          ),
          child: Icon(style.icon, size: 20, color: style.tone.strong),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(item.label, style: AppText.title)),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: AppSpacing.xxs),
      Flexible(child: Text(label, style: AppText.readableStrong)),
    ],
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _FieldLabel(icon: icon, label: label),
      const SizedBox(height: AppSpacing.xxs),
      child,
    ],
  );
}

/// A soft dashed tile, the target of "Attach a file".
class _DashedPainter extends CustomPainter {
  const _DashedPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppRadius.control),
        ),
      );
    final paint = Paint()
      ..color = AppColors.inputBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 9) {
        canvas.drawPath(metric.extractPath(at, at + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => false;
}

class _Files extends StatelessWidget {
  const _Files({
    required this.controller,
    required this.form,
    required this.isRequired,
  });

  final TicketDetailController controller;
  final TicketActionForm form;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final items = form.files.toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FieldLabel(
            icon: Icons.attach_file,
            label: isRequired
                ? '${TicketsTexts.filesLabel} *'
                : TicketsTexts.filesLabel,
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
          Semantics(
            button: true,
            label: items.isEmpty
                ? TicketsTexts.attach
                : TicketsTexts.attachAnother,
            excludeSemantics: true,
            child: InkWell(
              onTap: () => _choose(context),
              borderRadius: AppRadius.controlAll,
              child: CustomPaint(
                painter: const _DashedPainter(),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.attach_file,
                        size: 18,
                        color: AppColors.primaryStrong,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Flexible(
                        child: Text(
                          items.isEmpty
                              ? TicketsTexts.attach
                              : TicketsTexts.attachAnother,
                          style: AppText.readableStrong.copyWith(
                            color: AppColors.primaryStrong,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
        color: AppColors.white,
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
