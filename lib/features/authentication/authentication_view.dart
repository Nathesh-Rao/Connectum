import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_notice_banner.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_segmented_control.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_text_field.dart';
import 'authentication_controller.dart';
import 'widgets/option_picker_sheet.dart';

class AuthenticationView extends GetView<AuthenticationController> {
  const AuthenticationView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Obx(() {
        if (controller.isOffline) {
          return AppStateView(
            state: AppViewState.offline,
            onRetry: () {},
            child: const SizedBox.shrink(),
          );
        }
        return _Form(controller: controller);
      }),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.controller});

  final AuthenticationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final notice = c.session.loginNotice.value;
          if (notice == null) return const SizedBox(height: AppSpacing.md);
          return Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: AppNoticeBanner(message: notice, onDismiss: c.dismissNotice),
          );
        }),
        const Text('01 / YOUR ACCOUNT', style: AppText.label),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Image.asset('assets/images/connectum_logo.png', width: 40),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text('Connectum', style: AppText.heading),
        const SizedBox(height: AppSpacing.xs),
        const Text(
          'One account for every enterprise you work with.',
          style: AppText.readable,
        ),
        const Spacer(),
        Obx(
          () => AppSegmentedControl(
            labels: const ['Sign in', 'Create account'],
            selected: c.mode.value,
            onChanged: c.setMode,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => Text(
            c.isRegister
                ? 'Register your personal Connectum account.'
                : 'A secure code. No password to remember.',
            style: AppText.readable,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: c.email,
            label: 'Email address',
            hint: 'you@enterprise.com',
            keyboardType: TextInputType.emailAddress,
            textInputAction: c.isRegister
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: c.isRegister ? null : (_) => c.submit(),
            autofillHints: const [AutofillHints.email],
            errorText: c.fieldErrors['email'],
            onChanged: (_) => c.fieldErrors.remove('email'),
          ),
        ),
        Obx(
          () => c.isRegister
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: c.username,
                      label: 'Username',
                      textInputAction: TextInputAction.next,
                      errorText: c.fieldErrors['username'],
                      onChanged: (_) => c.fieldErrors.remove('username'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: c.mobile,
                      label: 'Mobile (optional)',
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      errorText: c.fieldErrors['mobile'],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: c.country,
                      label: 'Country (optional)',
                      readOnly: true,
                      suffix: const Icon(
                        Icons.expand_more,
                        color: AppColors.muted,
                      ),
                      errorText: c.fieldErrors['country'],
                      onTap: () async {
                        final options = await c.loadCountries();
                        if (!context.mounted || options.isEmpty) return;
                        final picked = await AppBottomSheet.show<String>(
                          context,
                          title: 'Country',
                          child: OptionPickerSheet(options: options),
                        );
                        if (picked != null) c.setCountry(picked);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: c.city,
                      label: 'City (optional)',
                      readOnly: true,
                      suffix: const Icon(
                        Icons.expand_more,
                        color: AppColors.muted,
                      ),
                      errorText: c.fieldErrors['city'],
                      onTap: () async {
                        final options = await c.loadCities();
                        if (!context.mounted || options.isEmpty) return;
                        final picked = await AppBottomSheet.show<String>(
                          context,
                          title: 'City',
                          child: OptionPickerSheet(options: options),
                        );
                        if (picked != null) c.city.text = picked;
                      },
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        Obx(() {
          final error = c.formError.value;
          if (error == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(error, style: AppText.error),
          );
        }),
        const SizedBox(height: AppSpacing.xl),
        Obx(
          () => AppButton.primary(
            label: c.isRegister ? 'Create account' : 'Sign in',
            icon: Icons.arrow_forward,
            isLoading: c.isBusy.value,
            onPressed: c.submit,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Center(
          child: Text(
            "We'll email you a one-time verification code.",
            style: AppText.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
