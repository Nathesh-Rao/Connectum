import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../data/models/ids.dart';
import '../form_controller.dart';
import '../models/field_input.dart';
import 'form_box.dart';

/// A booking time: the days and times the person named by another field can
/// be booked, minus what is already taken. The value is `yyyy-mm-dd HH:MM`.
class FormSlotField extends StatelessWidget {
  const FormSlotField({
    super.key,
    required this.controller,
    required this.input,
    this.row,
  });

  final FormController controller;
  final FieldInput input;
  final RowInput? row;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `2026-11-04` as "Wed 4 Nov".
  static String dayLabel(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  }

  static String shown(String value) {
    final parts = value.split(' ');
    return parts.length == 2 ? '${dayLabel(parts[0])}, ${parts[1]}' : value;
  }

  @override
  Widget build(BuildContext context) {
    final f = input.def;
    return Obx(() {
      final text = shown(idText(input.value.value));
      final hasPerson = controller.hasSlotPerson(f, row: row);
      final hint = hasPerson
          ? 'Choose a time'
          : 'Choose ${controller.slotOfCaption(f)} first';
      return FormBox(
        error: input.error,
        onTap: hasPerson ? () => _open(context) : null,
        trailing: const Icon(Icons.schedule, size: 18, color: AppColors.muted),
        child: Text(
          text.isEmpty ? hint : text,
          style: AppText.input.copyWith(
            color: text.isEmpty ? AppColors.muted : AppColors.ink,
          ),
        ),
      );
    });
  }

  void _open(BuildContext context) {
    final own = idText(input.value.value);
    unawaited(controller.loadSlots(input, row: row));
    AppBottomSheet.show<void>(
      context,
      title: input.def.caption,
      child: _SlotSheet(
        input: input,
        own: own,
        onRetry: () {
          input.slotPerson = null;
          controller.loadSlots(input, row: row);
        },
        onPick: (value) {
          controller.setValue(input, value, row: row);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _SlotSheet extends StatefulWidget {
  const _SlotSheet({
    required this.input,
    required this.own,
    required this.onPick,
    required this.onRetry,
  });

  final FieldInput input;
  final String own;
  final ValueChanged<String> onPick;
  final VoidCallback onRetry;

  @override
  State<_SlotSheet> createState() => _SlotSheetState();
}

class _SlotSheetState extends State<_SlotSheet> {
  final _day = RxnString();

  @override
  Widget build(BuildContext context) => Obx(() {
    final i = widget.input;
    final days = i.slotDays.value;
    final error = i.slotError.value;
    if (error != null) {
      return _Note(text: error, actionLabel: 'Retry', onAction: widget.onRetry);
    }
    if (days == null || i.isLoadingSlots.value) {
      return const _Note(text: 'Loading times…');
    }
    if (days.isEmpty) {
      return const _Note(text: 'No times are open at the moment.');
    }
    final current = idText(i.value.value);
    final picked = current.length >= 10 ? current.substring(0, 10) : '';
    final shownDay = days.firstWhere(
      (d) => d.date == (_day.value ?? picked),
      orElse: () => days.first,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: AppSpacing.chipHeight,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            children: [
              for (final d in days)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: _Chip(
                    label: FormSlotField.dayLabel(d.date),
                    isOn: d.date == shownDay.date,
                    onTap: () => _day.value = d.date,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final t in shownDay.times)
                _Chip(
                  label: t.time,
                  isOn: current == '${shownDay.date} ${t.time}',
                  isTaken:
                      !t.isFree && widget.own != '${shownDay.date} ${t.time}',
                  onTap: () => widget.onPick('${shownDay.date} ${t.time}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  });
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      children: [
        Text(text, textAlign: TextAlign.center, style: AppText.readable),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isOn,
    required this.onTap,
    this.isTaken = false,
  });

  final String label;
  final bool isOn;
  final bool isTaken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: isTaken ? null : onTap,
    child: Container(
      alignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: AppSpacing.chipHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: isOn
            ? AppColors.primaryTint
            : isTaken
            ? AppColors.fill
            : AppColors.white,
        borderRadius: AppRadius.controlAll,
        border: Border.all(
          color: isOn ? AppColors.primaryBright : AppColors.inputBorder,
        ),
      ),
      child: Text(
        label,
        style: AppText.readable.copyWith(
          color: isTaken
              ? AppColors.muted
              : isOn
              ? AppColors.primaryStrong
              : AppColors.ink,
          decoration: isTaken ? TextDecoration.lineThrough : null,
        ),
      ),
    ),
  );
}
