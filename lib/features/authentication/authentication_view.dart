import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/data/app_countries.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_ambient_backdrop.dart';
import '../../core/widgets/app_animated_size.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_invite_card.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_view.dart';
import '../../core/widgets/app_tab_bar.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/country_picker_sheet.dart';
import 'auth_validators.dart';
import 'authentication_controller.dart';
import 'widgets/option_picker_sheet.dart';

class AuthenticationView extends GetView<AuthenticationController> {
  const AuthenticationView({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      ambient: AppAmbientVariant.access,
      isScrollable: false,
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
    final viewport = MediaQuery.sizeOf(context).height;
    final heroGap = (viewport * _heroGapShare).clamp(8.0, 56.0);
    final fieldsGap = (viewport * _fieldsGapShare).clamp(24.0, 96.0);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppInviteSlot(invite: c.invite),
              const SizedBox(height: AppSpacing.lg),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('01 / YOUR ACCOUNT', style: AppText.eyebrow),
              ),
              SizedBox(height: heroGap),
              const _Hero(),
              SizedBox(height: fieldsGap),
              _Fields(controller: c),
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: AppButton.text(
                    label: 'Have an invite code or link?',
                    onPressed: c.openInviteSheet,
                  ),
                ),
                const _AccessFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The prototype's measured gaps (33 and 77) as shares of its frame height.
const double _heroGapShare = 33 / 844;
const double _fieldsGapShare = 77 / 844;

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppLogo(width: AppSpacing.heroLogoWidth),
        SizedBox(height: AppSpacing.heroGap),
        Text('Connectum', style: AppText.hero, textAlign: TextAlign.center),
        SizedBox(height: AppSpacing.heroTitleGap),
        Text(
          'One account for every enterprise you work with.',
          style: AppText.heroCopy,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _AccessFooter extends StatelessWidget {
  const _AccessFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check, size: 13, color: AppColors.muted),
          SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'Private by design. Connected by choice.',
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.controller});

  final AuthenticationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => AppTabBar(
            selectedIndex: c.mode.value,
            onChanged: c.selectTab,
            labels: AuthenticationController.tabLabels,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ModeSwitcher(controller: c),
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
            label: c.mode.value == 0 ? 'Sign in' : 'Send me a code',
            icon: Icons.chevron_right,
            isLoading: c.isBusy.value,
            onPressed: c.submit,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Center(
          child: Text(
            "We'll email you a one-time verification code.",
            style: AppText.caption,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// The form of the current tab. The outgoing one fades and shifts away from
/// the direction of travel while the incoming one arrives from that side; the
/// height follows (AnimatedSize), and the outgoing form takes no layout space.
class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.controller});

  final AuthenticationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isReduced = MediaQuery.disableAnimationsOf(context);
    return Obx(() {
      final index = c.mode.value;
      return AppAnimatedSize(
        duration: isReduced ? Duration.zero : AppDurations.base,
        curve: AppCurves.out,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: isReduced ? AppDurations.reduced : AppDurations.base,
          switchInCurve: AppCurves.out,
          switchOutCurve: AppCurves.out,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [
              for (final p in previous)
                Positioned(top: 0, left: 0, right: 0, child: p),
              ?current,
            ],
          ),
          transitionBuilder: (child, animation) {
            final isIncoming = child.key == ValueKey<int>(index);
            final shift = isReduced
                ? 0.0
                : AppDistances.modeShift * c.direction * (isIncoming ? 1 : -1);
            return FadeTransition(
              opacity: animation,
              child: AnimatedBuilder(
                animation: animation,
                builder: (_, w) => Transform.translate(
                  offset: Offset(shift * (1 - animation.value), 0),
                  child: w,
                ),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(index),
            child: switch (index) {
              0 => _SignInForm(controller: c),
              1 => _SetupForm(controller: c),
              _ => _RegisterForm(controller: c),
            },
          ),
        ),
      );
    });
  }
}

class _SignInForm extends StatelessWidget {
  const _SignInForm({required this.controller});

  final AuthenticationController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'A secure code. No password to remember.',
          style: AppText.readable,
        ),
        const SizedBox(height: AppSpacing.lg),
        _EmailField(controller: controller, isSignIn: true),
      ],
    );
  }
}

class _SetupForm extends StatelessWidget {
  const _SetupForm({required this.controller});

  final AuthenticationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create a new enterprise. You become its administrator, and it gets its own Connectum ID.',
          style: AppText.readable,
        ),
        const SizedBox(height: AppSpacing.lg),
        Obx(
          () => AppTextField(
            controller: c.orgName,
            focusNode: c.focus['org'],
            label: 'Enterprise name',
            hint: 'e.g. Agile Labs',
            leading: const _FieldIcon(Icons.apartment_outlined),
            textInputAction: TextInputAction.next,
            errorText: c.errorFor('org'),
            onChanged: (_) => c.changed('org'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Obx(
          () => AppTextField(
            controller: c.ownerName,
            focusNode: c.focus['name'],
            label: 'Your name',
            hint: 'Full name',
            leading: const _FieldIcon(Icons.person_outline),
            textInputAction: TextInputAction.next,
            errorText: c.errorFor('name'),
            onChanged: (_) => c.changed('name'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _EmailField(controller: c, isSignIn: false),
        const SizedBox(height: AppSpacing.md),
        _MobileField(
          controller: c,
          isSetup: true,
          label: 'Mobile',
          field: c.setupMobile,
          iso: c.setupIso,
          errorKey: 'setupMobile',
        ),
      ],
    );
  }
}

class _RegisterForm extends StatelessWidget {
  const _RegisterForm({required this.controller});

  final AuthenticationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final isReduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => AppTextField(
            controller: c.username,
            focusNode: c.focus['username'],
            label: 'Username',
            hint: 'e.g. john_doe',
            helperText: AuthValidators.usernameHint,
            leading: const _FieldIcon(Icons.person_outline),
            textInputAction: TextInputAction.next,
            errorText: c.errorFor('username'),
            onChanged: (_) => c.changed('username'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _EmailField(controller: c, isSignIn: false),
        const SizedBox(height: AppSpacing.sm),
        Obx(
          () => AppAnimatedSize(
            duration: isReduced ? Duration.zero : AppDurations.base,
            curve: AppCurves.out,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: isReduced ? AppDurations.reduced : AppDurations.base,
              child: c.isMoreOpen.value
                  ? _MoreFields(key: const ValueKey('more'), controller: c)
                  : Align(
                      key: const ValueKey('link'),
                      alignment: Alignment.centerLeft,
                      child: AppButton.text(
                        label: '+ Add phone and location (optional)',
                        tone: AppTextButtonTone.accent,
                        onPressed: c.toggleMore,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MoreFields extends StatelessWidget {
  const _MoreFields({super.key, required this.controller});

  final AuthenticationController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
        _MobileField(
          controller: c,
          isSetup: false,
          label: 'Mobile (optional)',
          field: c.regMobile,
          iso: c.regIso,
          errorKey: 'regMobile',
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: c.country,
          label: 'Country (optional)',
          readOnly: true,
          leading: const _FieldIcon(Icons.public),
          suffix: const Icon(Icons.expand_more, color: AppColors.muted),
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
          controller: c.state,
          label: 'State or region (optional)',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: c.city,
          label: 'City (optional)',
          textInputAction: TextInputAction.done,
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
              if (picked != null) c.city.text = picked;
            },
          ),
        ),
      ],
    );
  }
}

class _FieldIcon extends StatelessWidget {
  const _FieldIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 18, color: AppColors.muted);
}

class _EmailField extends StatelessWidget {
  const _EmailField({required this.controller, required this.isSignIn});

  final AuthenticationController controller;
  final bool isSignIn;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(
      () => AppTextField(
        controller: c.email,
        focusNode: c.focus['email'],
        label: 'Email address',
        hint: isSignIn ? 'you@enterprise.com' : 'you@company.com',
        leading: isSignIn
            ? const Text('@', style: AppText.leadingGlyph)
            : const _FieldIcon(Icons.mail_outline),
        keyboardType: TextInputType.emailAddress,
        textInputAction: isSignIn ? TextInputAction.done : TextInputAction.next,
        onSubmitted: isSignIn ? (_) => c.submit() : null,
        autofillHints: const [AutofillHints.email],
        errorText: c.errorFor('email'),
        onChanged: (_) => c.changed('email'),
      ),
    );
  }
}

class _MobileField extends StatelessWidget {
  const _MobileField({
    required this.controller,
    required this.isSetup,
    required this.label,
    required this.field,
    required this.iso,
    required this.errorKey,
  });

  final AuthenticationController controller;
  final bool isSetup;
  final String label;
  final TextEditingController field;
  final RxString iso;
  final String errorKey;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final country = c.countryFor(iso);
      return AppTextField(
        controller: field,
        focusNode: c.focus[errorKey],
        label: label,
        hint: 'Mobile number',
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
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
                if (picked != null) c.setIso(isSetup, picked);
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
        errorText: c.errorFor(errorKey),
        onChanged: (_) => c.changed(errorKey),
      );
    });
  }
}
