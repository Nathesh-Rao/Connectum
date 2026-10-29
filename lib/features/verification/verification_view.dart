import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_ambient_backdrop.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_flex_gap.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_state_image.dart';
import '../../core/widgets/app_text_field.dart';
import 'verification_controller.dart';

class VerificationView extends GetView<VerificationController> {
  const VerificationView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      ambient: AppAmbientVariant.access,
      body: Obx(() {
        if (c.blockedReasons.isNotEmpty) {
          return _Blocked(reasons: c.blockedReasons, onBack: c.changeEmail);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Transform.translate(
                        offset: const Offset(-12, 0),
                        child: AppButton.icon(
                          icon: Icons.chevron_left,
                          semanticLabel: 'Back to email',
                          onPressed: c.changeEmail,
                        ),
                      ),
                      const Spacer(),
                      const Text('02 / VERIFY', style: AppText.eyebrow),
                    ],
                  ),
                  const AppFlexGap(flex: 9, min: 0, max: 24),
                  const Center(
                    child: AppLogo(width: AppSpacing.verifyLogoWidth),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Check your inbox',
                    style: AppText.heading,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.heroTitleGap),
                  const Text(
                    'We sent a 6-digit code to',
                    style: AppText.heroCopy,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    c.email,
                    style: AppText.heroCopyStrong,
                    textAlign: TextAlign.center,
                  ),
                  const AppFlexGap(flex: 77, min: 24, max: 96),
                  const Text('Verification code', style: AppText.fieldLabel),
                  const SizedBox(height: AppSpacing.sm),
                  _Shake(
                    tick: c.shakeTick,
                    child: Row(
                      children: [
                        for (
                          var i = 0;
                          i < VerificationController.length;
                          i++
                        ) ...[
                          if (i > 0)
                            const SizedBox(width: AppSpacing.otpCellGap),
                          Expanded(
                            child: AppTextField(
                              controller: c.cells[i],
                              focusNode: c.focusNodes[i],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              textStyle: AppText.digit,
                              minHeight: AppSpacing.otpCellHeight,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(AppRadius.cell),
                              ),
                              horizontalPadding: 0,
                              autofillHints: i == 0
                                  ? const [AutofillHints.oneTimeCode]
                                  : null,
                              onChanged: (v) => c.onCellChanged(i, v),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Obx(() {
                    final text = c.message.value;
                    final tries = c.triesLeft.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        text ??
                            (tries < VerificationController.maxTries
                                ? '$tries ${tries == 1 ? 'try' : 'tries'} left'
                                : 'The code is valid for 5 minutes.'),
                        style: AppText.caption,
                      ),
                    );
                  }),
                  const SizedBox(height: AppSpacing.xs),
                  Obx(
                    () => AppButton.primary(
                      label: 'Verify & continue',
                      icon: Icons.chevron_right,
                      isLoading: c.isBusy.value,
                      onPressed: c.isLocked ? null : c.submit,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AppButton.text(
                        label: 'Change email',
                        tone: AppTextButtonTone.accent,
                        onPressed: c.changeEmail,
                      ),
                      Obx(
                        () => AppButton.text(
                          label: c.resendIn.value > 0
                              ? 'Send again in ${c.resendIn.value}s'
                              : 'Send again',
                          onPressed: c.resendIn.value > 0 ? null : c.resend,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1, color: AppColors.line),
                ],
              ),
            ),
            const _Footer(),
          ],
        );
      }),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check, size: 13, color: AppColors.muted),
          SizedBox(width: AppSpacing.xs),
          Text(
            'Private by design. Connected by choice.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.reasons, required this.onBack});

  final List<String> reasons;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Center(child: AppStateImage(kind: AppStateImageKind.locked)),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          "This account needs a step the mobile app doesn't support yet",
          style: AppText.title,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Required: ${reasons.join(', ')}.', style: AppText.readable),
        const SizedBox(height: AppSpacing.xl),
        AppButton.secondary(label: 'Back', onPressed: onBack),
        const Spacer(),
      ],
    );
  }
}

class _Shake extends StatefulWidget {
  const _Shake({required this.tick, required this.child});

  final RxInt tick;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: AppDurations.base,
  );
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    _worker = ever(widget.tick, (_) => _animation.forward(from: 0));
  }

  @override
  void dispose() {
    _worker?.dispose();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          sin(_animation.value * pi * 4) * 8 * (1 - _animation.value),
          0,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
