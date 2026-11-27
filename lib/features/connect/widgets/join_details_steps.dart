import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/data/app_countries.dart';
import '../../../core/data/country_lookup.dart';
import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/authentication/authentication.dart';
import '../../forms/widgets/form_box.dart';
import '../connect_controller.dart';
import '../models/join_flow.dart';

/// The employee step of the web's JoinWizard: the employee code, or branch,
/// department and designation when the organisation does not require a code.
class JoinEmployeeStep extends StatelessWidget {
  const JoinEmployeeStep({super.key, required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final flow = c.joinFlow.value;
      if (flow == null) return const SizedBox.shrink();
      final isOpenPlace =
          !flow.page.isCodeRequired && flow.value('employeeCode').isEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TextRow(
            controller: c,
            field: 'employeeCode',
            label: 'Employee code',
            hint: 'e.g. EMP-1042',
            helper: flow.page.isCodeRequired
                ? 'Your administrator gave you this code.'
                : 'Your administrator can give you one. Without it, an administrator approves you.',
            capitalization: TextCapitalization.characters,
            autocorrect: false,
          ),
          if (isOpenPlace) ...[
            const SizedBox(height: AppSpacing.md),
            _PickRow(
              controller: c,
              field: 'branch',
              label: 'Branch',
              options: flow.page.branches,
            ),
            const SizedBox(height: AppSpacing.md),
            _PickRow(
              controller: c,
              field: 'department',
              label: 'Department',
              options: flow.page.departments,
            ),
            const SizedBox(height: AppSpacing.md),
            _PickRow(
              controller: c,
              field: 'designation',
              label: 'Designation',
              options: flow.designations,
            ),
          ],
        ],
      );
    });
  }
}

/// The details step: name, username, mobile and, for an associate, country,
/// city, PIN and what the category requires.
class JoinDetailsStep extends StatelessWidget {
  const JoinDetailsStep({super.key, required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final flow = c.joinFlow.value;
      if (flow == null) return const SizedBox.shrink();
      final wanted = flow.wanted;
      const gap = SizedBox(height: AppSpacing.md);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (flow.isClaiming) ...[
            Text.rich(
              TextSpan(
                style: AppText.readable,
                children: [
                  const TextSpan(text: 'We match your code with '),
                  TextSpan(
                    text: c.identityEmail,
                    style: AppText.readableStrong,
                  ),
                  const TextSpan(
                    text:
                        ". If your administrator has a different email on file, add your mobile number below.",
                  ),
                ],
              ),
            ),
            gap,
          ],
          _TextRow(
            controller: c,
            field: 'name',
            label: flow.isClaiming ? 'Full name (optional)' : 'Full name',
            hint: 'Your name',
            capitalization: TextCapitalization.words,
          ),
          gap,
          _TextRow(
            controller: c,
            field: 'username',
            label: 'Your username here',
            hint: 'e.g. john_doe',
            helper: 'How people in this enterprise see you.',
            autocorrect: false,
          ),
          gap,
          _MobileRow(controller: c),
          if (flow.isAssociate) ...[
            gap,
            _CountryRow(controller: c),
            gap,
            _CityRow(controller: c),
            gap,
            _TextRow(
              controller: c,
              field: 'pin',
              label: 'Postal PIN (optional)',
              hint: 'PIN',
            ),
          ],
          if (wanted.contains('address')) ...[
            gap,
            _TextRow(controller: c, field: 'address', label: 'Address'),
          ],
          if (wanted.contains('gender')) ...[
            gap,
            _PickRow(
              controller: c,
              field: 'gender',
              label: 'Gender',
              options: JoinFlow.genders,
            ),
          ],
          if (wanted.contains('dob')) ...[gap, _DateRow(controller: c)],
          if (wanted.contains('education')) ...[
            gap,
            _TextRow(controller: c, field: 'education', label: 'Education'),
          ],
          if (wanted.contains('skills')) ...[
            gap,
            _TextRow(
              controller: c,
              field: 'skills',
              label: 'Skills',
              helper: 'Separate with commas',
            ),
          ],
          if (wanted.contains('branch')) ...[
            gap,
            _PickRow(
              controller: c,
              field: 'branch',
              label: 'Branch',
              options: flow.page.branches,
            ),
          ],
          if (wanted.contains('department')) ...[
            gap,
            _PickRow(
              controller: c,
              field: 'department',
              label: 'Department',
              options: flow.page.departments,
            ),
          ],
        ],
      );
    });
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

class _FieldIcon extends StatelessWidget {
  const _FieldIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 18, color: AppColors.muted);
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.controller,
    required this.field,
    required this.label,
    this.hint,
    this.helper,
    this.capitalization = TextCapitalization.none,
    this.autocorrect = true,
  });

  final ConnectController controller;
  final String field;
  final String label;
  final String? hint;
  final String? helper;
  final TextCapitalization capitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) => Obx(
    () => AppTextField(
      controller: controller.textFor(field),
      label: label,
      hint: hint,
      helperText: helper,
      errorText: controller.fieldErrors[field],
      textCapitalization: capitalization,
      autocorrect: autocorrect,
      textInputAction: TextInputAction.next,
      onChanged: (v) => controller.setValue(field, v),
    ),
  );
}

class _MobileRow extends StatelessWidget {
  const _MobileRow({required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final iso = c.joinFlow.value?.values['mobileIso'];
      final country = CountryLookup.byIso(iso) ?? CountryLookup.deviceDefault();
      return AppTextField(
        controller: c.textFor('mobile'),
        label: 'Mobile number',
        hint: 'Mobile number',
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        errorText: c.fieldErrors['mobile'],
        onChanged: (v) => c.setValue('mobile', v),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FieldIcon(Icons.phone_outlined),
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final picked = await AppBottomSheet.show<AppCountry>(
                  context,
                  title: 'Country code',
                  child: const CountryPickerSheet(),
                );
                if (picked != null) c.pickMobileCountry(picked);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${country.iso} +${country.dial}',
                    style: AppText.readableStrong,
                  ),
                  const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => AppTextField(
        controller: c.textFor('country'),
        label: 'Country (optional)',
        readOnly: true,
        leading: const _FieldIcon(Icons.public),
        suffix: const Icon(Icons.expand_more, color: AppColors.muted),
        errorText: c.fieldErrors['country'],
        onTap: () async {
          final options = await c.loadCountries();
          if (!context.mounted || options.isEmpty) return;
          final picked = await AppBottomSheet.show<String>(
            context,
            title: 'Country',
            child: OptionPickerSheet(options: options),
          );
          if (picked != null) c.pickCountry(picked);
        },
      ),
    );
  }
}

class _CityRow extends StatelessWidget {
  const _CityRow({required this.controller});

  final ConnectController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => AppTextField(
        controller: c.textFor('city'),
        label: 'City (optional)',
        errorText: c.fieldErrors['city'],
        textInputAction: TextInputAction.next,
        onChanged: (v) => c.setValue('city', v),
        suffix: IconButton(
          tooltip: 'Choose a city',
          icon: const Icon(Icons.expand_more, color: AppColors.muted),
          onPressed: () async {
            final options = await c.loadCities();
            if (!context.mounted || options.isEmpty) return;
            final picked = await AppBottomSheet.show<String>(
              context,
              title: 'City',
              child: OptionPickerSheet(options: options),
            );
            if (picked != null) c.setValue('city', picked);
          },
        ),
      ),
    );
  }
}

/// A value picked from a list, in the look of a text field.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.controller,
    required this.field,
    required this.label,
    required this.options,
  });

  final ConnectController controller;
  final String field;
  final String label;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label(label),
        Obx(() {
          final text = c.joinFlow.value?.value(field) ?? '';
          return FormBox(
            errorText: c.fieldErrors[field],
            onTap: options.isEmpty
                ? null
                : () async {
                    final picked = await AppBottomSheet.show<String>(
                      context,
                      title: label,
                      child: OptionPickerSheet(options: options),
                    );
                    if (picked != null) c.setValue(field, picked);
                  },
            trailing: const Icon(
              Icons.expand_more,
              size: 18,
              color: AppColors.muted,
            ),
            child: Text(
              text.isNotEmpty
                  ? text
                  : options.isEmpty
                  ? 'Nothing to choose from'
                  : 'Select…',
              style: AppText.input.copyWith(
                color: text.isEmpty ? AppColors.muted : AppColors.ink,
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.controller});

  final ConnectController controller;

  static String _text(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Date of birth'),
        Obx(() {
          final text = c.joinFlow.value?.value('dob') ?? '';
          return FormBox(
            errorText: c.fieldErrors['dob'],
            onTap: () async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final current = DateTime.tryParse(text);
              final picked = await showDatePicker(
                context: context,
                initialDate: current ?? today,
                firstDate: DateTime(1900),
                lastDate: today,
              );
              if (picked != null) c.setValue('dob', _text(picked));
            },
            trailing: const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: AppColors.muted,
            ),
            child: Text(
              text.isEmpty ? 'Select a date' : text,
              style: AppText.input.copyWith(
                color: text.isEmpty ? AppColors.muted : AppColors.ink,
              ),
            ),
          );
        }),
      ],
    );
  }
}
