import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/utils/utils.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/profile/profile.dart';
import '../../data/profile/personal_details.dart';
import 'profile_details_controller.dart';

class ProfileDetailsView extends GetView<ProfileDetailsController> {
  const ProfileDetailsView({super.key});

  Future<void> _pickDob(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = DetailsRules.dobFromWire(controller.dob.value);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(today.year - 30, today.month, today.day),
      firstDate: DetailsRules.earliestBirth,
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) controller.setDob(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppDiscardGuard(
      isDirty: c.isDirty,
      title: ProfileTexts.discardTitle,
      message: ProfileTexts.discardBody,
      discardLabel: ProfileTexts.discard,
      keepLabel: ProfileTexts.keepEditing,
      child: AppScaffold(
        isScrollable: false,
        showOfflineBar: true,
        padding: EdgeInsets.zero,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => AppButton.icon(
                      icon: Icons.arrow_back,
                      semanticLabel: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      ProfileTexts.detailsTitle,
                      style: AppText.heading,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Obx(
                () => AppStateView(
                  state: c.state.value,
                  onRetry: c.load,
                  errorMessage: c.errorMessage.value,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: _Form(
                      controller: c,
                      onPickDob: () => _pickDob(context),
                    ),
                  ),
                ),
              ),
            ),
            Obx(() {
              if (c.state.value != AppViewState.content) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: AppButton.primary(
                  label: 'Save details',
                  isCentered: true,
                  isLoading: c.isSaving.value,
                  onPressed: c.isSaving.value
                      ? null
                      : () async {
                          if (await c.save()) Get.back<void>();
                        },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.controller, required this.onPickDob});

  final ProfileDetailsController controller;
  final VoidCallback onPickDob;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: AppRadius.cardAll,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 18,
                color: AppColors.primaryStrong,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  ProfileTexts.detailsPrivate,
                  style: AppText.readable.copyWith(
                    color: AppColors.primaryStrong,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Label('Gender'),
        Obx(
          () => Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final e in ProfileDetailsController.genders.entries)
                _Choice(
                  label: e.value,
                  isSelected: c.gender.value == e.key,
                  onTap: () => c.selectGender(e.key),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Label('Date of birth'),
        Obx(() {
          final date = DetailsRules.dobFromWire(c.dob.value);
          final text = date == null
              ? 'Select date'
              : MaterialLocalizations.of(context).formatMediumDate(date);
          return Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Date of birth, $text',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: onPickDob,
                    borderRadius: AppRadius.controlAll,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: AppSpacing.controlHeight,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.controlPaddingX,
                        vertical: AppSpacing.xs,
                      ),
                      alignment: AlignmentDirectional.centerStart,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: AppRadius.controlAll,
                        border: Border.all(color: AppColors.inputBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              text,
                              style: AppText.input.copyWith(
                                color: date == null
                                    ? AppColors.tertiary
                                    : AppColors.ink,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (date != null)
                IconButton(
                  tooltip: 'Clear date of birth',
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTapTarget,
                    minHeight: AppSpacing.minTapTarget,
                  ),
                  icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                  onPressed: () => c.setDob(null),
                ),
            ],
          );
        }),
        const SizedBox(height: AppSpacing.lg),
        _Limited(
          label: 'Address',
          hint: 'Street, city, postal code',
          controller: c.address,
          limit: DetailsRules.addressBytes,
          maxLines: 3,
          keyboardType: TextInputType.streetAddress,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Limited(
          label: 'Education',
          hint: 'e.g. B.Tech Computer Science, MBA',
          controller: c.education,
          limit: DetailsRules.educationBytes,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Label('Skills (comma separated)'),
        AppTextField(
          controller: c.skills,
          hint: 'e.g. React, Erlang, Product Management',
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: AppSpacing.xs),
        Obx(() {
          final problem = c.skillsError.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${c.skillList.length}/${DetailsRules.maxSkills} skills, '
                'each up to ${DetailsRules.skillBytes} bytes',
                key: const ValueKey('skills-counter'),
                style: AppText.caption.copyWith(
                  color: problem == null ? AppColors.muted : AppColors.error,
                ),
              ),
              if (c.skillList.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final s in c.skillList)
                      _SkillChip(
                        label: s,
                        isTooLong:
                            DetailsRules.bytes(s) > DetailsRules.skillBytes,
                      ),
                  ],
                ),
              ],
            ],
          );
        }),
        Obx(() {
          final message = c.error.value;
          if (message == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Semantics(
              liveRegion: true,
              child: Text(message, style: AppText.error),
            ),
          );
        }),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(text, style: AppText.fieldLabel),
  );
}

/// A text field with a byte limit: what is typed is cut to it and the
/// counter says "n/limit bytes".
class _Limited extends StatelessWidget {
  const _Limited({
    required this.label,
    required this.hint,
    required this.controller,
    required this.limit,
    this.maxLines = 1,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int limit;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: label,
          hint: hint,
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [
            TransformFormatter((t) => DetailsRules.typed(t, limit)),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final n = DetailsRules.bytes(value.text);
            return Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '$n/$limit bytes',
                key: ValueKey('counter-$label'),
                style: AppText.caption.copyWith(
                  color: n >= limit - 10 ? AppColors.ink : AppColors.muted,
                  fontWeight: n >= limit - 10
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: isSelected,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pillAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryTint : AppColors.white,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.line,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: AppText.readableStrong.copyWith(
                      color: isSelected
                          ? AppColors.primaryStrong
                          : AppColors.ink,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.primaryStrong,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({required this.label, required this.isTooLong});

  final String label;
  final bool isTooLong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: isTooLong ? AppColors.noFill : AppColors.primaryTint,
      borderRadius: AppRadius.pillAll,
      border: isTooLong ? Border.all(color: AppColors.error) : null,
    ),
    child: Text(
      label,
      style: AppText.readableStrong.copyWith(
        color: isTooLong ? AppColors.error : AppColors.primaryStrong,
      ),
    ),
  );
}
